from __future__ import annotations

import secrets
import smtplib
import uuid
from dataclasses import dataclass
from email.message import EmailMessage
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import AppError, ErrorCode
from app.core.identifiers import normalise_email, normalise_phone
from app.core.timeutils import now_utc
from app.models.enums import OtpPurpose, UserStatus, VerificationChannel
from app.models.identity import User
from app.models.otp import OtpAttempt, OtpRequest
from app.repositories.user_repository import UserRepository
from app.security.passwords import constant_time_equals, keyed_digest
from app.services.audit_service import AuditService
from app.services.user_service import UserService


@dataclass(frozen=True)
class OtpDeliveryResult:
    request: OtpRequest
    code: str
    channel: VerificationChannel
    target: str


class OtpService:
    def __init__(self, session: Session, settings: Settings | None = None) -> None:
        self.session = session
        self.settings = settings or get_settings()
        self.users = UserRepository(session)
        self.user_service = UserService(session)

    @staticmethod
    def _code_for(length: int = 6) -> str:
        return "".join(secrets.choice("0123456789") for _ in range(length))

    @staticmethod
    def _clean_target(identifier: str) -> tuple[str, VerificationChannel]:
        value = (identifier or "").strip()
        if not value:
            raise AppError(
                "Enter an email address or phone number.",
                code=ErrorCode.VALIDATION_ERROR,
                status_code=422,
            )
        if "@" in value:
            normalised = normalise_email(value)
            if not normalised:
                raise AppError(
                    "That email address is not valid.",
                    code=ErrorCode.VALIDATION_ERROR,
                    status_code=422,
                )
            return normalised, VerificationChannel.EMAIL
        phone, _ = normalise_phone(value)
        if not phone:
            raise AppError(
                "That phone number is not valid.",
                code=ErrorCode.VALIDATION_ERROR,
                status_code=422,
            )
        return phone, VerificationChannel.SMS

    def _pending_request(
        self,
        *,
        target: str,
        purpose: OtpPurpose,
    ) -> OtpRequest | None:
        target_hash = keyed_digest(target, self.settings.OTP_HASH_PEPPER)
        stmt = (
            select(OtpRequest)
            .where(
                OtpRequest.target_hash == target_hash,
                OtpRequest.purpose == purpose,
                OtpRequest.invalidated_at.is_(None),
                OtpRequest.consumed_at.is_(None),
                OtpRequest.expires_at > now_utc(),
            )
            .order_by(OtpRequest.issued_at.desc(), OtpRequest.created_at.desc())
            .limit(1)
        )
        return self.session.execute(stmt).scalar_one_or_none()

    def _mailbox_path(self, *, target: str, code: str) -> Path:
        root = self.settings.mailbox_root
        if root is None:
            raise AppError(
                "No mailbox directory is configured for OTP delivery.",
                code=ErrorCode.INTERNAL_ERROR,
                status_code=500,
            )
        root.mkdir(parents=True, exist_ok=True)
        safe_target = target.replace("@", "_at_")
        safe_target = safe_target.replace("+", "_")
        return root / f"otp_{safe_target}_{now_utc().strftime('%Y%m%d%H%M%S%f')}_{code}.txt"

    def _deliver(self, *, target: str, code: str, channel: VerificationChannel) -> str:
        if self.settings.smtp_configured:
            msg = EmailMessage()
            msg["Subject"] = "PlantDoctor verification code"
            msg["From"] = f"{self.settings.SMTP_FROM_NAME} <{self.settings.SMTP_FROM_EMAIL}>"
            msg["To"] = target
            msg.set_content(
                "Your PlantDoctor verification code is "
                f"{code}. This code expires in {self.settings.OTP_TTL_SECONDS} seconds."
            )
            with smtplib.SMTP(
                self.settings.SMTP_HOST,
                self.settings.SMTP_PORT,
                timeout=self.settings.SMTP_TIMEOUT_SECONDS,
            ) as smtp:
                if self.settings.SMTP_USE_TLS:
                    smtp.starttls()
                if self.settings.SMTP_USERNAME:
                    smtp.login(self.settings.SMTP_USERNAME, self.settings.SMTP_PASSWORD)
                smtp.send_message(msg)
            return "smtp"

        path = self._mailbox_path(target=target, code=code)
        path.write_text(
            "PlantDoctor OTP\n"
            f"Target: {target}\n"
            f"Code: {code}\n"
            f"Expires in: {self.settings.OTP_TTL_SECONDS} seconds\n",
            encoding="utf-8",
        )
        return str(path)

    def request_otp(
        self,
        identifier: str,
        *,
        purpose: OtpPurpose,
        client_ip: str | None,
        user_agent: str | None,
        resend: bool = False,
    ) -> OtpDeliveryResult:
        target, channel = self._clean_target(identifier)
        user = self.users.get_by_identifier(
            email_normalised=target if channel is VerificationChannel.EMAIL else None,
            phone_e164=target if channel is VerificationChannel.SMS else None,
        )

        if purpose == OtpPurpose.EMAIL_VERIFICATION and user is not None:
            if user.email_normalised and user.email_verified_at is not None and user.email_normalised == target:
                raise AppError(
                    "This email address has already been verified.",
                    code=ErrorCode.OTP_ALREADY_VERIFIED,
                    status_code=409,
                )
        if purpose == OtpPurpose.PASSWORD_RESET and user is None:
            return self._return_generic_success(target, channel)

        pending = self._pending_request(target=target, purpose=purpose)
        if pending is not None and not resend:
            if pending.last_sent_at is not None:
                seconds_since = int((now_utc() - pending.last_sent_at).total_seconds())
                if seconds_since < self.settings.OTP_RESEND_COOLDOWN_SECONDS:
                    raise AppError(
                        "Please wait a moment before requesting another code.",
                        code=ErrorCode.OTP_RESEND_COOLDOWN,
                        status_code=429,
                    )
            if pending.resend_count >= self.settings.OTP_MAX_RESENDS:
                raise AppError(
                    "Too many codes have been sent for this address.",
                    code=ErrorCode.OTP_RESEND_LIMIT,
                    status_code=429,
                )

        if pending is not None:
            pending.invalidated_at = now_utc()
            pending.invalidated_reason = "resent"

        code = self._code_for(self.settings.OTP_LENGTH)
        request = OtpRequest(
            purpose=purpose,
            channel=channel,
            target=target,
            target_hash=keyed_digest(target, self.settings.OTP_HASH_PEPPER),
            code_hash=keyed_digest(code, self.settings.OTP_HASH_PEPPER),
            user_id=user.id if user is not None else None,
            ip_address=client_ip,
            user_agent=(user_agent or "")[:400] or None,
            issued_at=now_utc(),
            expires_at=now_utc() + __import__("datetime").timedelta(seconds=self.settings.OTP_TTL_SECONDS),
            last_sent_at=now_utc(),
            max_attempts=self.settings.OTP_MAX_VERIFY_ATTEMPTS,
            max_resends=self.settings.OTP_MAX_RESENDS,
        )
        self.session.add(request)
        self.session.flush()

        delivery = self._deliver(target=target, code=code, channel=channel)
        request.provider = "smtp" if "smtp" == delivery else "mailbox"
        request.delivery_reference = delivery
        request.last_sent_at = now_utc()
        if pending is not None:
            request.resend_count = (pending.resend_count or 0) + 1
        AuditService.record(
            self.session,
            action="otp.requested",
            resource_type="otp",
            resource_id=str(request.id),
            changes={"target_hash": request.target_hash, "purpose": purpose.value, "channel": channel.value},
            status_code=200,
            ip_address=client_ip,
            user_agent=user_agent,
        )
        return OtpDeliveryResult(request=request, code=code, channel=channel, target=target)

    def _return_generic_success(self, target: str, channel: VerificationChannel) -> OtpDeliveryResult:
        return OtpDeliveryResult(
            request=OtpRequest(
                purpose=OtpPurpose.EMAIL_VERIFICATION,
                channel=channel,
                target=target,
                target_hash=keyed_digest(target, self.settings.OTP_HASH_PEPPER),
                code_hash=keyed_digest("000000", self.settings.OTP_HASH_PEPPER),
                issued_at=now_utc(),
                expires_at=now_utc(),
                last_sent_at=None,
                max_attempts=1,
                max_resends=1,
            ),
            code="000000",
            channel=channel,
            target=target,
        )

    def verify_otp(
        self,
        identifier: str,
        *,
        code: str,
        purpose: OtpPurpose,
        client_ip: str | None,
        user_agent: str | None,
    ) -> tuple[OtpRequest, User]:
        target, _ = self._clean_target(identifier)
        target_hash = keyed_digest(target, self.settings.OTP_HASH_PEPPER)
        stmt = (
            select(OtpRequest)
            .where(
                OtpRequest.target_hash == target_hash,
                OtpRequest.purpose == purpose,
                OtpRequest.invalidated_at.is_(None),
            )
            .order_by(OtpRequest.issued_at.desc(), OtpRequest.created_at.desc())
            .limit(1)
        )
        request = self.session.execute(stmt).scalar_one_or_none()
        if request is None:
            raise AppError(
                "That code is invalid or has expired.",
                code=ErrorCode.INVALID_OTP,
                status_code=401,
            )

        if request.expires_at <= now_utc():
            request.consumed_at = now_utc()
            raise AppError(
                "That code has expired. Please request a new one.",
                code=ErrorCode.OTP_EXPIRED,
                status_code=401,
            )

        if request.attempts_used >= request.max_attempts:
            raise AppError(
                "Too many incorrect attempts. Please request a new code.",
                code=ErrorCode.OTP_ATTEMPT_LIMIT,
                status_code=429,
            )

        if not constant_time_equals(keyed_digest(code.strip(), self.settings.OTP_HASH_PEPPER), request.code_hash):
            request.attempts_used += 1
            self.session.add(
                OtpAttempt(
                    otp_request_id=request.id,
                    attempt_number=request.attempts_used,
                    succeeded=False,
                    failure_reason="bad_code",
                    ip_address=client_ip,
                    user_agent=(user_agent or "")[:400] or None,
                )
            )
            if request.attempts_used >= request.max_attempts:
                request.invalidated_at = now_utc()
                request.invalidated_reason = "max_attempts"
            raise AppError(
                "That code is incorrect.",
                code=ErrorCode.INVALID_OTP,
                status_code=401,
            )

        request.attempts_used += 1
        request.consumed_at = now_utc()
        self.session.add(
            OtpAttempt(
                otp_request_id=request.id,
                attempt_number=request.attempts_used,
                succeeded=True,
                ip_address=client_ip,
                user_agent=(user_agent or "")[:400] or None,
            )
        )

        user = request.user_id and self.users.get(request.user_id)
        if user is None:
            user = self.users.get_by_identifier(
                email_normalised=target if "@" in target else None,
                phone_e164=target if "@" not in target else None,
            )
        if user is None:
            raise AppError(
                "No account matches that address.",
                code=ErrorCode.ACCOUNT_NOT_FOUND,
                status_code=404,
            )

        if purpose == OtpPurpose.EMAIL_VERIFICATION and user.email_normalised == target:
            self.user_service.mark_email_verified(user)
        elif purpose == OtpPurpose.PHONE_VERIFICATION and user.phone_e164 == target:
            self.user_service.mark_phone_verified(user)
        elif purpose == OtpPurpose.PASSWORD_RESET:
            user.status = UserStatus.ACTIVE

        if user.status != UserStatus.ACTIVE and user.status != UserStatus.PENDING_VERIFICATION:
            user.status = UserStatus.ACTIVE

        AuditService.record(
            self.session,
            action="otp.verified",
            resource_type="otp",
            resource_id=str(request.id),
            actor_user_id=user.id,
            changes={"purpose": purpose.value, "target": target, "verified": True},
            status_code=200,
            ip_address=client_ip,
            user_agent=user_agent,
        )
        return request, user

    def reset_password(
        self,
        *,
        identifier: str,
        code: str,
        new_password: str,
        client_ip: str | None,
        user_agent: str | None,
    ) -> User:
        _, user = self.verify_otp(
            identifier,
            code=code,
            purpose=OtpPurpose.PASSWORD_RESET,
            client_ip=client_ip,
            user_agent=user_agent,
        )
        self.user_service.set_password(
            user,
            new_password,
            revoke_sessions=True,
            actor=user.id,
            reason="password_reset",
        )
        return user

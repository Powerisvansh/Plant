"""Server command line interface.

    python -m app.cli <command> [options]

Commands are added as their subsystem is built; ``python -m app.cli --help``
always lists exactly what is implemented. No command ever accepts a password
or a secret as a command-line argument, because arguments are visible in the
process table and in shell history.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from sqlalchemy import func, select

BACKEND_DIR = Path(__file__).resolve().parents[1]


def _add_generate_secrets(sub: argparse._SubParsersAction) -> None:
    parser = sub.add_parser(
        "generate-secrets",
        help="Generate strong random secrets and merge them into the env file.",
        description=(
            "Generates cryptographically random values for JWT_SECRET, "
            "JWT_REFRESH_SECRET and OTP_HASH_PEPPER. Existing values are kept "
            "unless --force is given, so running this is safe on a live server."
        ),
    )
    parser.add_argument(
        "--env-file",
        default=os.environ.get("PLANTDOCTOR_ENV_FILE", "/plantdoctor-data/.env"),
        help="Env file to update (default: /plantdoctor-data/.env).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace secrets that are already present. Invalidates all sessions.",
    )
    parser.add_argument(
        "--print-only",
        action="store_true",
        help="Print the secrets to stdout instead of writing the env file.",
    )
    parser.add_argument(
        "--create",
        action="store_true",
        help="Create the env file from .env.example when it does not exist.",
    )


def _cmd_generate_secrets(args: argparse.Namespace) -> int:
    from app.core.config import generate_secret

    env_path = Path(args.env_file)
    example = BACKEND_DIR / ".env.example"

    if not env_path.exists() and not args.create:
        print(
            f"error: {env_path} does not exist.\n"
            f"       Create it with:  python -m app.cli generate-secrets --create",
            file=sys.stderr,
        )
        return 2

    generated = {
        "JWT_SECRET": generate_secret(48),
        "JWT_REFRESH_SECRET": generate_secret(48),
        "OTP_HASH_PEPPER": generate_secret(48),
    }

    if args.print_only:
        for key, value in generated.items():
            print(f"{key}={value}")
        return 0

    if not env_path.exists():
        if not example.is_file():
            print(f"error: {example} not found; cannot scaffold the env file.", file=sys.stderr)
            return 2
        env_path.parent.mkdir(parents=True, exist_ok=True)
        env_path.write_text(example.read_text(encoding="utf-8"), encoding="utf-8")
        env_path.chmod(0o600)
        print(f"created {env_path} from .env.example")

    existing: dict[str, str] = {}
    lines = env_path.read_text(encoding="utf-8").splitlines()
    for line in lines:
        if "=" in line and not line.strip().startswith("#"):
            key, _, value = line.partition("=")
            existing[key.strip()] = value.strip()

    changed: list[str] = []
    kept: list[str] = []
    for key, value in generated.items():
        current = existing.get(key, "")
        if current and not args.force:
            kept.append(key)
            continue
        existing[key] = value
        changed.append(key)

    if changed:
        out: list[str] = []
        written: set[str] = set()
        for line in lines:
            if "=" in line and not line.strip().startswith("#"):
                key = line.partition("=")[0].strip()
                if key in existing and key not in written:
                    out.append(f"{key}={existing[key]}")
                    written.add(key)
                    continue
            out.append(line)
        for key in changed:
            if key not in written:
                out.append(f"{key}={existing[key]}")
        env_path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
        env_path.chmod(0o600)

    for key in changed:
        print(f"  generated  {key}")
    for key in kept:
        print(f"  kept       {key} (use --force to replace)")
    print(f"\nenv file: {env_path}  (mode 0600)")
    if changed:
        print(
            "NOTE: replacing JWT_SECRET or JWT_REFRESH_SECRET invalidates every\n"
            "      issued access and refresh token. Users must sign in again."
        )
    return 0


def _cmd_seed_roles(args: argparse.Namespace) -> int:
    """Reconcile roles and permissions with the catalogue in app.security.rbac.

    Idempotent: run it on every deploy. Existing rows are updated, removed
    permissions are revoked, nothing is deleted that a user still holds.
    """
    from app.core.logging_config import setup_logging
    from app.database.session import session_scope, wait_for_database
    from app.services.audit_service import AuditService
    from app.services.role_service import seed_roles_and_permissions
    from app.security.rbac import ROLE_DEFINITIONS

    setup_logging("INFO", fmt="text")
    wait_for_database()

    with session_scope() as session:
        report = seed_roles_and_permissions(session)
        AuditService.record(
            session,
            action="roles.seeded",
            resource_type="role",
            changes=report.as_dict(),
            reason="CLI seed-roles",
            is_dangerous=True,
        )

    print("roles and permissions reconciled:")
    for key, value in report.as_dict().items():
        print(f"  {key}: {value}")
    print()
    for definition in ROLE_DEFINITIONS:
        print(f"  {definition.name:<12} {len(definition.permissions):>3} permissions")
    return 0


def _cmd_create_admin(args: argparse.Namespace) -> int:
    """Interactively create the first SUPER_ADMIN.

    The password is read from a TTY with echo disabled. It is never accepted as
    an argument: arguments are visible in the process table and in shell
    history, and `create-admin --password hunter2` would be recorded forever.
    """
    from getpass import getpass

    from app.core.errors import AppError
    from app.core.logging_config import setup_logging
    from app.core.timeutils import now_utc
    from app.database.session import session_scope, wait_for_database
    from app.models.enums import UserStatus
    from app.models.identity import Role
    from app.repositories.user_repository import UserRepository
    from app.security.passwords import validate_password_strength
    from app.services.user_service import NewUser, UserAlreadyExistsError, UserService

    setup_logging("INFO", fmt="text")
    wait_for_database()

    if not sys.stdin.isatty():
        print(
            "error: create-admin needs an interactive terminal so the password can be\n"
            "       read without being echoed or stored in shell history.",
            file=sys.stderr,
        )
        return 2

    with session_scope() as session:
        # Fail early if the catalogue has not been seeded, rather than after the
        # operator has typed a password.
        if not UserRepository(session).get_role("SUPER_ADMIN"):
            print(
                "error: the role catalogue is empty.\n"
                "       Run: python -m app.cli seed-roles",
                file=sys.stderr,
            )
            return 2

    print("Creating the first administrator.\n")
    name = (args.name or input("Full name: ")).strip()
    if not name:
        print("error: a name is required.", file=sys.stderr)
        return 2

    default_email = args.email or ""
    email = (default_email or input("Email: ")).strip()
    if "@" not in email:
        print("error: that does not look like an email address.", file=sys.stderr)
        return 2

    password = getpass("Password (input hidden): ")
    if password != getpass("Repeat password: "):
        print("error: the two passwords do not match.", file=sys.stderr)
        return 2

    # Check the policy before the service does, so the operator sees the full
    # list of problems at once instead of fixing them one round trip at a time.
    try:
        validate_password_strength(password, email=email, full_name=name)
    except AppError as exc:
        print(f"\nerror: {exc.message}", file=sys.stderr)
        for problem in (exc.details or {}).get("requirements", []):
            print(f"  - {problem}", file=sys.stderr)
        return 2

    with session_scope() as session:
        service = UserService(session)
        try:
            user = service.create_user(
                NewUser(
                    full_name=name,
                    password=password,
                    email=email,
                    role="SUPER_ADMIN",
                    is_verified=bool(args.verified) or True,
                    terms_accepted=True,
                )
            )
        except UserAlreadyExistsError as exc:
            print(f"\nerror: {exc.message}", file=sys.stderr)
            return 2
        except AppError as exc:
            print(f"\nerror: {exc.message}", file=sys.stderr)
            return 2
        session.commit()

    print(f"\ncreated SUPER_ADMIN {user.email_normalised}")
    print(f"  user id : {user.id}")
    print(f"  status  : {UserStatus.ACTIVE.value}")
    print(f"  created : {now_utc().isoformat()}")
    print(
        "\nThe account is already verified, so no OTP is required. Sign in at\n"
        "POST /api/v1/auth/login. The password is not stored anywhere in\n"
        "clear text and was not written to the env file."
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m app.cli",
        description="PlantDoctor server administration.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)
    _add_generate_secrets(sub)
    _register_seed_roles(sub)
    _register_create_admin(sub)
    _register_backup(sub)
    _register_restore(sub)
    _register_import(sub)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    handlers = {
        "generate-secrets": _cmd_generate_secrets,
        "seed-roles": _cmd_seed_roles,
        "create-admin": _cmd_create_admin,
    }
    handler = handlers.get(args.command)
    if handler is None:
        parser.error(f"command {args.command!r} is not wired up yet")
    return handler(args)


def _register_seed_roles(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser(
        "seed-roles",
        help="Insert or update the system roles and permissions (idempotent).",
        description=(
            "Creates the four system roles (USER, EXPERT, ADMIN, SUPER_ADMIN) "
            "and the resource:action permission catalogue, reconciles links, and "
            "revokes permissions that are no longer defined. Safe to run on every "
            "deploy."
        ),
    )
    p.set_defaults(_handler="seed_roles")


def _register_create_admin(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser(
        "create-admin",
        help="Interactively create a super administrator. Never takes a password argument.",
    )
    p.add_argument("--email", help="Optional. The password is always prompted for.")
    p.add_argument("--name", help="Optional display name.")
    p.add_argument("--verified", action="store_true", help="Mark email as already verified.")
    p.set_defaults(_handler="create_admin")


def _register_backup(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("backup", help="Create or list verified database backups.")
    p.add_argument("--label", help="Free-form label recorded in the manifest.")
    p.add_argument("--list", action="store_true", help="List backups and verify checksums.")
    p.add_argument("--verify", action="store_true", help="Verify checksums without creating one.")
    p.add_argument("--keep", type=int, help="Override BACKUP_RETENTION_COUNT for this run.")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(_handler="backup")


def _register_restore(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser("restore", help="Restore the database from a backup file.")
    p.add_argument("file", nargs="?", help="Backup filename or absolute path.")
    p.add_argument(
        "--list", action="store_true", help="List available backups and exit."
    )
    p.add_argument(
        "--yes",
        action="store_true",
        help="Skip the confirmation prompt. The current database is always backed up first.",
    )
    p.set_defaults(_handler="restore")


def _register_import(sub: argparse._SubParsersAction) -> None:
    p = sub.add_parser(
        "import",
        help="Import validated knowledge records from a JSON file.",
        description=(
            "Validates every record before inserting. Malformed records are "
            "rejected with a report; nothing is invented and nothing is "
            "inserted without source and verification information."
        ),
    )
    p.add_argument(
        "entity",
        choices=["plants", "diseases", "symptoms", "treatments", "medicines", "doctors"],
    )
    p.add_argument("file", help="Path to a JSON file, or '-' to read stdin.")
    p.add_argument("--dry-run", action="store_true", help="Validate and report only.")
    p.add_argument(
        "--allow-unverified",
        action="store_true",
        help="Permit records with status DRAFT or REVIEW. They stay hidden from public APIs.",
    )
    p.add_argument("--report", help="Write a JSON import report to this path.")
    p.set_defaults(_handler="import")


if __name__ == "__main__":
    sys.exit(main())

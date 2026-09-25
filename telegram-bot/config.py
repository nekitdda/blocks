import os
from pathlib import Path
from dotenv import load_dotenv

BASE_DIR = Path(__file__).parent
load_dotenv(BASE_DIR / ".env")

BOT_TOKEN: str = os.getenv("BOT_TOKEN", "")
ADMIN_IDS_RAW: str = os.getenv("ADMIN_IDS", "")
ADMIN_IDS: list[int] = [
    int(x.strip()) for x in ADMIN_IDS_RAW.split(",") if x.strip().isdigit()
]

DB_PATH = BASE_DIR / "bot.db"
LOGO_PATH = BASE_DIR / "assets" / "logo.png"

# === РАЗДЕЛЫ ===
# Ключ слева не меняй. Текст справа - название кнопки.
# Файл: telegram-bot/config.py:23
CATEGORIES: dict[str, str] = {
    "kazan": "Казань",
    "sevastopol": "Севастополь",
    "perm": "Пермь",
    "cp": "ЦП",
}

GREETING_TEXT = (
    "Тихо. Ты внутри.\n"
    "Выбирай раздел. Лишнего не спрашивай."
)

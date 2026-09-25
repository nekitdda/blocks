import asyncio
import logging
from aiogram import Bot, Dispatcher, Router, F
from aiogram.filters import Command, StateFilter
from aiogram.types import (
    Message,
    CallbackQuery,
    ReplyKeyboardMarkup,
    KeyboardButton,
    InlineKeyboardMarkup,
    InlineKeyboardButton,
    FSInputFile,
)
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import StatesGroup, State

import config
import database

logging.basicConfig(level=logging.INFO)
router = Router()
user_last_category: dict[int, str] = {}


class AddItem(StatesGroup):
    category = State()
    title = State()
    description = State()
    file = State()


class Broadcast(StatesGroup):
    text = State()


def is_admin(user_id: int) -> bool:
    return user_id in config.ADMIN_IDS


def main_keyboard() -> ReplyKeyboardMarkup:
    buttons = [[KeyboardButton(text=name)] for name in config.CATEGORIES.values()]
    return ReplyKeyboardMarkup(keyboard=buttons, resize_keyboard=True)


def categories_inline(prefix: str = "cat") -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text=name, callback_data=f"{prefix}:{key}")]
            for key, name in config.CATEGORIES.items()
        ]
    )


def items_keyboard(items: list[tuple]) -> InlineKeyboardMarkup:
    kb = [
        [InlineKeyboardButton(text=title, callback_data=f"item:{item_id}")]
        for item_id, title, *_ in items
    ]
    kb.append([InlineKeyboardButton(text="Назад", callback_data="back")])
    return InlineKeyboardMarkup(inline_keyboard=kb)


def admin_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text="Добавить позицию", callback_data="adm:add")],
            [InlineKeyboardButton(text="Удалить позицию", callback_data="adm:del")],
            [InlineKeyboardButton(text="Статистика", callback_data="adm:stats")],
            [InlineKeyboardButton(text="Рассылка", callback_data="adm:broadcast")],
        ]
    )


async def send_greeting(message: Message) -> None:
    # Лого грузим строго из telegram-bot/assets/logo.png
    if config.LOGO_PATH.is_file():
        try:
            photo = FSInputFile(config.LOGO_PATH)
            await message.answer_photo(
                photo, caption=config.GREETING_TEXT, reply_markup=main_keyboard()
            )
            return
        except Exception as e:
            logging.exception("logo send failed: %s", e)
            # падаем в текстовый вариант ниже, чтобы старт не молчал
    else:
        logging.warning("logo not found: %s", config.LOGO_PATH)
    await message.answer(config.GREETING_TEXT, reply_markup=main_keyboard())


async def show_category(chat_message: Message, category_key: str) -> None:
    items = await database.get_items_by_category(category_key)
    cat_name = config.CATEGORIES.get(category_key, category_key)
    if not items:
        await chat_message.answer(f"{cat_name}. Пусто. Зайди позже.")
        return
    text = f"{cat_name}. В наличии:\n\n" + "\n".join(
        f"- {title}" for _, title, *_ in items
    )
    text += "\n\nНажми кнопку или напиши название. Отправлю."
    await chat_message.answer(text, reply_markup=items_keyboard(items))


async def send_item(message: Message, item: tuple) -> None:
    _id, _cat, title, description, file_type, file_id = item
    caption = f"{title}"
    if description:
        caption += f"\n\n{description}"
    try:
        if file_type == "photo" and file_id:
            await message.answer_photo(photo=file_id, caption=caption)
        elif file_type == "document" and file_id:
            await message.answer_document(document=file_id, caption=caption)
        elif file_type == "video" and file_id:
            await message.answer_video(video=file_id, caption=caption)
        else:
            await message.answer(caption)
    except Exception:
        logging.exception("send_item failed")
        await message.answer(f"{title}\n\n{description}\n\nФайл не ушел. Напиши админу.")


@router.message(Command("start"))
async def cmd_start(message: Message):
    await database.add_user(
        message.from_user.id,
        message.from_user.username,
        message.from_user.full_name,
    )
    await send_greeting(message)


@router.message(Command("myid"))
async def cmd_myid(message: Message):
    await message.answer(f"ID: {message.from_user.id}")


@router.message(Command("admin"))
async def cmd_admin(message: Message):
    if not is_admin(message.from_user.id):
        await message.answer("Доступа нет. Узнай ID через /myid и добавь в .env в ADMIN_IDS.")
        return
    await message.answer("Панель. Выбирай.", reply_markup=admin_keyboard())


@router.callback_query(F.data == "back")
async def cb_back(call: CallbackQuery):
    await call.message.answer("Раздел:", reply_markup=main_keyboard())
    await call.answer()


@router.callback_query(F.data.startswith("cat:"))
async def cb_category(call: CallbackQuery):
    key = call.data.split(":", 1)[1]
    if key not in config.CATEGORIES:
        await call.answer("Нет такого раздела", show_alert=True)
        return
    user_last_category[call.from_user.id] = key
    items = await database.get_items_by_category(key)
    cat_name = config.CATEGORIES[key]
    if not items:
        await call.message.answer(f"{cat_name}. Пусто.")
        await call.answer()
        return
    text = f"{cat_name}. В наличии:\n\n" + "\n".join(
        f"- {title}" for _, title, *_ in items
    )
    text += "\n\nНажми кнопку или напиши название."
    await call.message.answer(text, reply_markup=items_keyboard(items))
    await call.answer()


@router.callback_query(F.data.startswith("item:"))
async def cb_item(call: CallbackQuery):
    try:
        item_id = int(call.data.split(":", 1)[1])
    except ValueError:
        await call.answer("Ошибка", show_alert=True)
        return
    item = await database.get_item(item_id)
    if not item:
        await call.answer("Позиция удалена", show_alert=True)
        return
    await send_item(call.message, item)
    await call.answer()


@router.callback_query(F.data == "adm:add")
async def adm_add_start(call: CallbackQuery, state: FSMContext):
    if not is_admin(call.from_user.id):
        await call.answer("Нет доступа", show_alert=True)
        return
    await state.set_state(AddItem.category)
    await call.message.answer("Шаг 1/4. Раздел:", reply_markup=categories_inline("cat"))
    await call.answer()


@router.callback_query(AddItem.category, F.data.startswith("cat:"))
async def adm_add_category(call: CallbackQuery, state: FSMContext):
    key = call.data.split(":", 1)[1]
    await state.update_data(category=key)
    await state.set_state(AddItem.title)
    await call.message.answer(
        f"Раздел: {config.CATEGORIES.get(key)}\nШаг 2/4. Пришли название позиции текстом:"
    )
    await call.answer()


@router.message(AddItem.title, F.text)
async def adm_add_title(message: Message, state: FSMContext):
    await state.update_data(title=message.text.strip())
    await state.set_state(AddItem.description)
    await message.answer("Шаг 3/4. Пришли описание. Или отправь - чтобы пропустить:")


@router.message(AddItem.description, F.text)
async def adm_add_description(message: Message, state: FSMContext):
    desc = "" if message.text.strip() == "-" else message.text.strip()
    await state.update_data(description=desc)
    await state.set_state(AddItem.file)
    await message.answer("Шаг 4/4. Пришли фото / файл / видео. Или отправь - чтобы только текст.")


@router.message(AddItem.file, F.photo | F.document | F.video | F.text)
async def adm_add_file(message: Message, state: FSMContext):
    data = await state.get_data()
    file_type, file_id = "text", ""
    if message.photo:
        file_type, file_id = "photo", message.photo[-1].file_id
    elif message.document:
        file_type, file_id = "document", message.document.file_id
    elif message.video:
        file_type, file_id = "video", message.video.file_id
    elif not (message.text and message.text.strip() == "-"):
        await message.answer("Пришли фото/файл или -.")
        return

    item_id = await database.add_item(
        category_key=data["category"],
        title=data["title"],
        description=data.get("description", ""),
        file_type=file_type,
        file_id=file_id,
    )
    await state.clear()
    await message.answer(
        f"Готово. {data['title']} в разделе {config.CATEGORIES[data['category']]}. ID {item_id}.",
        reply_markup=main_keyboard(),
    )


@router.callback_query(F.data == "adm:del")
async def adm_del_start(call: CallbackQuery):
    if not is_admin(call.from_user.id):
        await call.answer("Нет доступа", show_alert=True)
        return
    kb = categories_inline("delcat")
    await call.message.answer("Что чистим. Выбери раздел:", reply_markup=kb)
    await call.answer()


@router.callback_query(F.data.startswith("delcat:"))
async def adm_del_list(call: CallbackQuery):
    if not is_admin(call.from_user.id):
        await call.answer("Нет доступа", show_alert=True)
        return
    key = call.data.split(":", 1)[1]
    items = await database.get_items_by_category(key)
    if not items:
        await call.message.answer("Здесь пусто.")
        await call.answer()
        return
    kb = InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text=title, callback_data=f"del:{item_id}")]
            for item_id, title, *_ in items
        ]
    )
    await call.message.answer("Нажми чтобы удалить:", reply_markup=kb)
    await call.answer()


@router.callback_query(F.data.startswith("del:"))
async def adm_del_confirm(call: CallbackQuery):
    if not is_admin(call.from_user.id):
        await call.answer("Нет доступа", show_alert=True)
        return
    item_id = int(call.data.split(":", 1)[1])
    await database.delete_item(item_id)
    await call.message.answer(f"Удалено. ID {item_id}.")
    await call.answer()


@router.callback_query(F.data == "adm:stats")
async def adm_stats(call: CallbackQuery):
    if not is_admin(call.from_user.id):
        await call.answer("Нет доступа", show_alert=True)
        return
    stats = await database.get_stats()
    lines = [f"Пользователей: {stats['users']}"]
    for key, name in config.CATEGORIES.items():
        lines.append(f"{name}: {stats['by_category'].get(key, 0)}")
    await call.message.answer("\n".join(lines))
    await call.answer()


@router.callback_query(F.data == "adm:broadcast")
async def adm_broadcast_start(call: CallbackQuery, state: FSMContext):
    if not is_admin(call.from_user.id):
        await call.answer("Нет доступа", show_alert=True)
        return
    await state.set_state(Broadcast.text)
    await call.message.answer("Пришли текст рассылки. /cancel - отмена.")
    await call.answer()


@router.message(Broadcast.text, F.text)
async def adm_broadcast_send(message: Message, state: FSMContext):
    if message.text == "/cancel":
        await state.clear()
        await message.answer("Отменено.")
        return
    users = await database.get_all_users()
    ok, fail = 0, 0
    for (uid,) in users:
        try:
            await message.bot.send_message(uid, message.text)
            ok += 1
        except Exception:
            fail += 1
    await state.clear()
    await message.answer(f"Готово. Ушло: {ok}. Ошибки: {fail}.")


@router.message(F.text)
async def handle_text(message: Message, state: FSMContext):
    if await state.get_state() is not None:
        return
    text = (message.text or "").strip()

    for key, name in config.CATEGORIES.items():
        if text == name:
            user_last_category[message.from_user.id] = key
            await show_category(message, key)
            return

    last_cat = user_last_category.get(message.from_user.id)
    item = None
    if last_cat:
        item = await database.find_item_by_text(last_cat, text)
    if not item:
        item = await database.find_item_by_text(None, text)

    if item:
        await send_item(message, item)
    else:
        await message.answer(
            "Не найдено. Жми раздел снизу.",
            reply_markup=main_keyboard(),
        )


async def main() -> None:
    if not config.BOT_TOKEN:
        raise RuntimeError("Нет BOT_TOKEN. Создай .env по примеру .env.example")
    await database.init_db()
    bot = Bot(token=config.BOT_TOKEN)
    dp = Dispatcher()
    dp.include_router(router)
    await bot.delete_webhook(drop_pending_updates=True)
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())

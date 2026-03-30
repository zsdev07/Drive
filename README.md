# ZX Drive
[![Ask DeepWiki](https://devin.ai/assets/askdeepwiki.png)](https://deepwiki.com/zsdev07/Drive.git)

ZX Drive is a cross-platform cloud storage application built with Flutter that uniquely leverages the Telegram API to provide 5TB of free, private, and secure storage.

## How It Works

The application operates by using a personal Telegram bot and a private channel that you control as its storage backend.

-   **File Storage:** Files are uploaded as documents to your private Telegram channel via the Telegram Bot API.
-   **Metadata Management:** A local SQLite database, managed by the `Drift` persistence library, stores all file and folder metadata (names, sizes, Telegram file IDs, folder structure). This enables fast, offline-first access to your file index.
-   **User Interface:** The Flutter frontend, with state managed by `Riverpod`, provides a familiar and intuitive cloud drive interface on top of this architecture.

## Features

-   **Telegram-Powered Storage:** Directly uses your Telegram account's cloud storage, offering up to 5TB for free.
-   **Complete File Management:** Perform all standard drive operations: upload, download, rename, move, and search for files.
-   **Folder Organization:** Create, rename, and delete folders to organize your files. Includes breadcrumb navigation for easy traversal.
-   **Starred & Trash:** Mark important files by starring them and move unwanted files to a trash bin for later restoration or permanent deletion.
-   **Efficient Uploads:** A dedicated queue manages multiple file uploads with real-time progress indicators.
-   **Local Security:** Secure your drive with a 4-digit PIN for local app access.
-   **Sleek UI:** A modern, dark-themed interface designed for a great user experience.

## Setup & Configuration

To use the app, you need to connect it to your own Telegram bot and channel.

1.  **Create a Telegram Bot:**
    -   Open Telegram and search for `@BotFather`.
    -   Start a chat and use the `/newbot` command.
    -   Follow the prompts to give your bot a name and a username.
    -   `@BotFather` will provide you with a **Bot Token**. Copy and save this token.

2.  **Create a Private Channel:**
    -   In Telegram, create a new private channel.

3.  **Add Bot as Admin:**
    -   Go to your new channel's settings.
    -   Add your bot as an administrator with full permissions.

4.  **Get Channel ID:**
    -   Forward any message from your private channel to a bot like `@JsonDumpBot` or `@userinfobot`.
    -   The bot will reply with a JSON object. Find the `chat.id` or `forward_from_chat.id` field. This is your **Channel ID** (it typically starts with `-100`).

5.  **Launch the App:**
    -   When you first open ZX Drive, it will ask for your **Bot Token** and **Channel ID**. Enter the credentials you saved to connect your storage backend.

## Tech Stack

-   **Framework:** Flutter
-   **State Management:** Flutter Riverpod
-   **Database:** Drift (Reactive persistence library for Flutter built on SQLite)
-   **Routing:** go_router
-   **HTTP Client:** Dio
-   **File Handling:** file_picker, open_file
-   **UI:** iconsax, percent_indicator
-   **Code Generation:** build_runner, riverpod_generator, drift_dev

## Getting Started (For Developers)

To build and run this project locally, follow these steps:

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/zsdev07/drive.git
    cd drive
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Run the code generator:**
    The project uses code generation for the database and state management. Run the following command to generate the necessary files:
    ```bash
    dart run build_runner build --delete-conflicting-outputs
    ```

4.  **Run the app:**
    ```bash
    flutter run

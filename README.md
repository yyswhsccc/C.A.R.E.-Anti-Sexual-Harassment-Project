# courage-to-act-moodle

Courage to Act - Moodle Gamification Project

## Project Overview

This project is a Moodle-based gamification plugin (or custom module) developed for the Courage to Act initiative. The goal is to extend Moodle's learning platform with features that foster engagement, motivation, and positive behavior change.

## Getting Started

### Prerequisites

- PHP 8.x
- MySQL 5.7.24+ or MariaDB (compatible with Moodle)
- Composer (optional, for dependency management)
- Moodle 4.x or higher (installed locally or on your server)
- [MAMP](https://www.mamp.info/en/) / XAMPP / LAMP stack recommended for local development

### Installation

1. **Clone this repository:**
    ```bash
    git clone https://github.com/yyswhsccc/courage-to-act-moodle.git
    ```
2. **Copy sample configuration:**
    ```bash
    cp config.sample.php config.php
    ```
    Edit `config.php` with your own database settings and environment variables.

3. **Install dependencies (if any):**
    ```bash
    composer install
    ```

4. **Set up your Moodle environment** (follow Moodle docs for plugin installation, e.g., place your plugin in `moodle/local/yourplugin`).

5. **Run Moodle setup** and complete installation via web browser (`http://localhost:8888/moodle`).

> **Note:** Never commit your actual `config.php` or sensitive data. Only share config.sample.php.

---

## Branch Strategy & Development Workflow

- **Main development happens in `feature/yourname-description` branches** (e.g., `feature/alice-login`).
- **Do NOT commit directly to `main`.**
- When your feature is ready, open a Pull Request (PR) to `main` and request a review.
- At least one code review is required before merging to `main`.

### How to start contributing

1. **Clone the repo:**
    ```bash
    git clone https://github.com/yyswhsccc/courage-to-act-moodle.git
    ```
2. **Switch to your branch:**
    ```bash
    git checkout feature/yourname-description
    ```
3. **Develop, commit, push** your changes.
4. **Open a Pull Request (PR) on GitHub** for code review and merging.

**Branch naming convention:**
- New feature: `feature/yourname-feature`
- Bugfix: `fix/yourname-issue`

All development should follow our [contribution guidelines](CONTRIBUTING.md).

---

## Project Structure
```
/
├── config.sample.php # Example config for local setup
├── CONTRIBUTING.md # Contribution guidelines
├── README.md # Project overview and setup instructions
├── .gitignore # Ignored files and folders
├── <your plugin code>
└── moodledata/ # (gitignored) Moodle's data storage, DO NOT COMMIT
```

## Configuration

See `config.sample.php` for all required environment variables and database settings.

## Issue Tracking & Tasks

- Use [GitHub Issues](../../issues) to report bugs, suggest features, or assign tasks.
- Project management may use [GitHub Projects](../../projects) for Kanban boards and sprint planning.

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for branch naming rules, PR workflow, and code review requirements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

### Notes

- Keep your local `config.php` and any sensitive files **out of version control**.
- For questions or onboarding new contributors, update this README as the project evolves.


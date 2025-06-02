# courage-to-act-moodle

Courage to Act - Moodle Gamification Project

![MIT License](https://img.shields.io/badge/license-MIT-green)
![Pull Requests Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)
![Issues](https://img.shields.io/github/issues/yyswhsccc/courage-to-act-moodle)

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

## FAQ

**Q: Where do I report bugs or request features?**  
A: Please open an issue on our [GitHub Issues page](https://github.com/yyswhsccc/courage-to-act-moodle/issues).

**Q: How can I join the project board for task tracking?**  
A: Contact @yyswhsccc in our team chat, or open an issue requesting access.

**Q: Who do I ask if I’m stuck or need code review?**  
A: Mention your question in our team chat and tag the relevant reviewer, or leave a comment on your PR.

**Q: Is there a coding style or branching policy I should follow?**  
A: Yes! See [CONTRIBUTING.md](CONTRIBUTING.md) for branch naming, PR, and review guidelines.

---

## Project Automation & Kanban Board

This project leverages GitHub Projects to streamline team collaboration and task management:

- **Kanban Board:**  
  We use a Kanban board with four columns: Todo, In Progress, Review, and Done.  
  [View the board here.](https://github.com/users/yyswhsccc/projects/1)

- **Built-in Automations:**  
  The board is fully automated:
    - New issues and PRs are automatically added to **Todo**.
    - When a PR receives a "changes requested" review, it moves to **Review**.
    - When a PR is approved, it moves to **Review**.
    - When a PR is merged or an issue is closed, it moves to **Done**.
    - Reopened items automatically return to **In Progress**.

**How to use:**
- Always create or link issues/PRs with the project board.
- Drag items between columns only when automation is not triggered (e.g., manual tasks).
- All team members can check the board for the current development status.

**Tip:**  
This automation ensures a transparent, up-to-date view of the project's progress without manual tracking!

---

You can see and customize the workflows under the Project board settings (Workflows tab).


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

- Use [GitHub Issues](https://github.com/yyswhsccc/courage-to-act-moodle/issues) to report bugs, suggest features, or assign tasks.
- Project management may use [GitHub Projects](https://github.com/users/yyswhsccc/projects/1) for Kanban boards and sprint planning.

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for branch naming rules, PR workflow, and code review requirements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

### Notes

- Keep your local `config.php` and any sensitive files **out of version control**.
- For questions or onboarding new contributors, update this README as the project evolves.


# Project Context for Claude CLI

Read README.md for context of this project.

## Coding Rules & Guidelines
1.  **Language:** Write all code, variable names, comments, and commit messages strictly in English.
2.  **Database Connection:** ALWAYS use standard connection strings via `process.env.DATABASE_URL` (Node) or `os.environ.get("DATABASE_URL")` (Python). Never hardcode credentials.
3.  **Keeping track of work done** Important changes, decisions, track of what work was already done and news concerning this project should be written to INFO.md
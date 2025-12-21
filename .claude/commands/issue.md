# Implement GitHub Issue

You are tasked with implementing a GitHub issue end-to-end. Follow these steps:

## 1. Fetch Issue Details
Use `gh issue view $ARGUMENTS` to get the full issue details including:
- Title
- Description
- Labels
- Acceptance criteria (if any)

## 2. Analyze and Plan
- Understand what needs to be implemented
- Identify which files need to be created or modified
- Consider the project architecture and conventions from CLAUDE.md

## 3. Create Feature Branch
Create a new branch from main with a descriptive name:
```bash
git checkout main
git pull origin main
git checkout -b feature/issue-$ARGUMENTS-<short-description>
```

## 4. Implement the Solution
- Write clean, well-documented code following project conventions
- Follow existing patterns in the codebase
- Add localization strings if needed (en + es)
- Build and verify there are no compilation errors

## 5. Test the Implementation
- Build the project to ensure no errors
- Run any existing tests
- Manually verify the implementation works as expected

## 6. Commit Changes
Create meaningful commits with clear messages describing what was done.

## 7. Push and Create PR
- Push the branch to origin
- Create a Pull Request that:
  - References the issue with "Closes #$ARGUMENTS"
  - Has a clear summary of changes
  - Includes a test plan

## 8. Review the PR
After creating the PR, launch a sub-agent to review it:
- Use the Task tool with a code review agent
- The agent should read the PR diff and provide feedback on:
  - Code quality and best practices
  - Potential bugs or issues
  - Suggestions for improvement
  - Compliance with project conventions
- If the review finds issues, address them before considering the task complete

## Important Notes
- Follow all guidelines in CLAUDE.md
- All code and commits must be in English
- User-facing strings must be localized (English + Spanish)
- Compile and test after each significant change

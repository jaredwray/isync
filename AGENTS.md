# AGENTS.md

This file gives instructions to AI agents and to humans who work in this repository.

## Project

isync is a native macOS app. It reads iMessages and Contacts on a Mac and sends them to a remote
API on a schedule.

- Language: Swift 6. Build system: Swift Package Manager.
- Do not add a third-party package dependency. If a change needs one, write an ADR in `docs/adr/`
  first and get approval from the maintainer.
- The app reads private data. Do not write message text, contact details, or API tokens to logs,
  to test fixtures, or to issues. Make all test data synthetic.

Run these checks before you push. CI runs the same checks on Linux and on macOS.

```sh
swift format lint --strict --recursive Package.swift Sources Tests
swift build --build-tests --disable-automatic-resolution -Xswiftc -warnings-as-errors
swift test --skip-build
```

- `Sources/ISyncCore` must build and pass its tests on Linux. Put each Apple-only import, such as
  `os` or `SQLite3`, in an `#if canImport(...)` block, and give the Linux path in the `#else` block.
  Put code that needs an Apple-only framework with no Linux path in `Sources/ISyncMac`.
- Use `swift format --in-place --recursive Package.swift Sources Tests` to fix the format.

## Agentic conventions
- Issue tracker: GitHub Issues
- Labels: bug, enhancement, documentation, question
- ADR directory: docs/adr/
- CHANGELOG: none (GitHub Release notes)
- Default branch: main
- Package manager: Swift Package Manager
- Code review: the agentic `code-review` skill on the Fable model (`claude-fable-5-1`), on each pull request before merge
- Merge: an agent can merge a pull request only when CI passes on the last commit, the Fable review has no open blocking or major finding, and each finding has a reply. A pull request that changes code or workflows must run at least one CI check.

## Simplified Technical English

Write in ASD-STE100 Simplified Technical English (STE). Get the current issue of the specification
free of charge from <https://www.asd-ste100.org>. STE applies to all text that you write for this
repository, its pull requests, and its issues. This text includes documentation, code comments,
commit messages, review replies, and changelog entries.

- Use approved STE words with their approved meanings. You can also use technical names and
  technical verbs. If you cannot confirm that a word is approved, use a short, common word with one
  meaning.
- Use one word for one meaning.
- Write an instruction in the imperative. Write one instruction in each sentence.
- Do not write more than 20 words in an instruction or 25 words in a descriptive sentence.
- Use the active voice.
- Use only the simple present, simple past, or simple future tense. Do not use the present perfect.
- Do not use the "-ing" form of a verb, except in a technical name.
- Do not write a noun cluster of more than three words.
- Do not omit articles, verbs, or subjects to make a sentence shorter.
- Write one topic in each paragraph. Do not write more than six sentences in a paragraph.
- Use a vertical list for steps, conditions, and other complex text.
- Do not change code, commands, identifiers, file paths, or quoted text to make them STE.
- Use STE for the text that you add or change. Do not rewrite other text only to make it STE.

## Test audit

Apply this gate to each test that a pull request adds, changes, or deletes. Apply it before you open
or update the pull request. This gate is the authoring gate of the `test-audit` skill in
`jaredwray/agentic`. If that skill is installed, use it.

Keep a new or changed test only if you can answer all four questions:

1. Which observable behavior, invariant, or contract does the test protect?
2. Which credible regression makes the test fail?
3. Why does the current coverage not find that regression? If a test or its table owns the
   contract, extend it. Do not add a near-duplicate test.
4. Does the test need an export, flag, or hook that no production caller uses? If yes, test at the
   real boundary.

- A regression test for a bug fix must fail on the code before the fix, for the intended reason.
- Do not keep a test that asserts nothing, restates the implementation, repeats the type checker,
  or only proves a mock.
- A coverage target does not lower this bar. Reach an uncovered line through its public entry
  point. If no caller can reach a branch, remove the branch. Do not add a test for it.
- Delete a test only when a different test proves its contract, or when the contract is gone. Do
  not delete a test because it fails.
- Record the gate in the verification list of the pull request body. List each test that you did
  not keep, rewrote, or deleted, and give the reason. For a deleted test, name the test that proves
  its contract, or show that the contract is gone.
- Do not audit tests that this pull request does not touch. Audit them in a separate pull request.

## Pull requests

The task does not stop when you open a pull request. Do these steps before you start a different
task:

1. Wait approximately 20 minutes for automated and human code reviews.
2. Read each new comment. Find each comment that has a finding, a question, or a change request.
3. Examine the code for each finding or change request. Decide if it is correct. Do not decide from
   who the reviewer is.
4. If it is correct, change the code. Run the same checks that CI runs. Push the change. On the
   thread, reply with what changed and the commit SHA.
5. If it is not correct, reply on the thread with the reason. Give the file and line. Do not
   resolve the thread. The reviewer closes it.
6. If a comment asks a question, answer it on the thread.
7. If CI fails, find the root cause and fix it. Do not skip or disable a test to make CI pass.
8. If you pushed a change or CI did not finish, do steps 1 to 7 again. Stop when CI passes and each
   finding, question, and change request has a reply.

Do not reply to a comment that needs no answer: your own replies, approvals, thanks, and bot status
notices. A reply to one of these comments starts the loop again.

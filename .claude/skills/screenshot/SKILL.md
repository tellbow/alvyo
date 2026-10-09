---
name: screenshot
description: Takes screenshots of a new feature or a fixed bug on the website or in the app (captured on Haiku by the screenshot-capture skill), checks them and shows them to the user in their terminal (Ghostty, Kitty graphics protocol) with a question whether they fit. Use after finishing user-visible work, as the screenshots rule says.
---

# Screenshot a feature and show it

Screenshots go to the scratchpad directory, never into the repository.

## 1. Decide what to capture

Which page or screen, in which state, and how to get there. Take light and
dark when colours changed, and 390 px wide when the phone layout is
affected; the app when the app changed.

## 2. Capture

Invoke the `screenshot-capture` skill (Skill tool). It runs on Haiku in a
forked subagent that does not see this conversation, so its arguments must
stand on their own:

- website or app, and the absolute output directory (the scratchpad)
- the page (URL) or screen, and the state: what to click, open, fill or
  hover, by German label or test id on the website, by widget key in the
  app
- the variants: light and dark, 1440 or 390 px wide
- a ready Playwright script or throwaway test, if you already have one

It starts what is missing of the local stack, captures, stops what it
started and answers with each image's path and what it shows, or what
failed.

## 3. Check, show, ask

Look at the images yourself first (Read). If something is wrong, fix it
and capture again (step 2) before showing them. Then show them to the
user:

```sh
python3 .claude/skills/screenshot/show.py /scratchpad/shot.png [/scratchpad/dark.png]
```

The images appear at the top right of the terminal Claude Code runs in,
side by side (the first on the right), at most half its width, leaving 20
rows free at the bottom (`--keep-rows`) for a question box. `--window`
opens a new Ghostty window instead.

Right after showing them, ask with AskUserQuestion what the user thinks:
the question names what each image shows (e.g. «rechts die Website, links
die App»), the options are «Passt» and what could be wrong («Ändern», with
the notes for what), so the user confirms or gives feedback in the box.
After the answer, remove the images
(`python3 .claude/skills/screenshot/show.py --clear`) and act on it. If the
user rejects the question to say something, they are still looking: keep
the images until their reply has been dealt with.

An image stays on the terminal until it is removed: the user cannot close
it. Each show removes the images shown before. Typing
`! python3 .claude/skills/screenshot/show.py --clear` removes them too.

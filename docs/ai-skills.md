# ORDM AI skills

ORDM ships an AI skill so the standard is usable by an agent, not just readable by a person. `ordm-data-modeling` authors or adapts ORDM-conformant models: use it to create a new canonical-core domain or outcome package, or to adapt and extend ORDM to your own environment (mapping your source systems, adding custom entities, tailoring outcome KPIs) while staying conformant. It points at the standard ([`docs/data-model-standards.md`](data-model-standards.md)) as its single source of truth, so it never drifts from the rules the CI enforces.

The skill uses the open [Agent Skills](https://agentskills.io) format: a folder with a `SKILL.md` (a `name` and a `description` in the frontmatter, then the instructions). Any AI coding tool that supports Agent Skills can use it.

## Where it lives

Tools look for skills in different folders, so the repository carries the same skill in two of them:

| Tool | Project skills (in this repository) | Personal skills |
|---|---|---|
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| GitHub Copilot in VS Code | `.github/skills/`, `.claude/skills/`, `.agents/skills/` | `~/.copilot/skills/`, `~/.claude/skills/`, `~/.agents/skills/` |
| OpenAI Codex | `.agents/skills/` | `~/.agents/skills/` |

For another tool, check its documentation for the folder it reads. Edit [`.agents/skills/ordm-data-modeling/`](../.agents/skills/ordm-data-modeling/); its copy in [`.claude/skills/ordm-data-modeling/`](../.claude/skills/ordm-data-modeling/) must stay identical, and a test checks that it does.

## How to plug it in

In this repository. Open it in your AI tool and the skill is discovered as a project skill. Nothing to install. Ask it to author a domain or to adapt ORDM to your sources; in Claude Code you can also run `/ordm-data-modeling`.

In your own or a customer repository. Copy the skill folder into your tool's personal skills folder:

```sh
# from a checkout of this repository
mkdir -p ~/.agents/skills ~/.claude/skills
cp -r .agents/skills/ordm-data-modeling ~/.agents/skills/   # Codex, Copilot
cp -r .agents/skills/ordm-data-modeling ~/.claude/skills/   # Claude Code, Copilot
```

Then keep ORDM itself available so the skill can read the standard: clone this repository alongside your work, or add it to your workspace, so that `docs/data-model-standards.md`, `CONTRIBUTING.md` and `standards/rules.yaml` are readable. The skill is deliberately thin: it carries the workflow and reads the rules from the standard rather than embedding a copy.

Keeping it current. Because the skill references the standard by path rather than restating it, a change to `docs/data-model-standards.md` or `standards/rules.yaml` takes effect immediately with no skill edit. Update the skill only when the workflow changes, not when a rule changes.

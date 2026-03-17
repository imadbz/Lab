# Lab Repository Guidelines

This repository is a collection of independent experiments. Each experiment lives in its own folder at the root of the repo.

## Rules

1. **One folder per experiment.** Every experiment gets its own top-level directory (e.g., `ray-tracing/`, `llm-eval-harness/`). Never mix work from different experiments in the same folder.
2. **Scope all work to an experiment folder.** When working on an idea, all new files, code, data, and notes must go inside that experiment's folder. Do not place experiment files at the repo root.
3. **Create the folder if it doesn't exist.** When starting a new experiment, create a new top-level directory with a short, descriptive name.
4. **Each experiment is self-contained.** An experiment folder should include its own README, dependencies, and any configuration it needs. Assume nothing is shared between experiments.
5. **Don't modify other experiments.** When working on one experiment, do not change files in another experiment's folder.
6. **Root-level files are for repo-wide concerns only.** Only files like this `CLAUDE.md`, the repo `README.md`, `.gitignore`, and similar repo-level config belong at the root.

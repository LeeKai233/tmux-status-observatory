SHELL := /usr/bin/env bash
PYTHON ?= python3

.PHONY: check install uninstall

check:
	bash -n bin/tmux-status-observatory tmux-status-observatory.tmux install.sh
	$(PYTHON) -m py_compile bin/tmux-status-sweep tests/test_sweep.py
	command -v shellcheck >/dev/null
	shellcheck bin/tmux-status-observatory tmux-status-observatory.tmux install.sh
	$(PYTHON) -m unittest discover -s tests -v

install:
	./install.sh

uninstall:
	./install.sh --uninstall

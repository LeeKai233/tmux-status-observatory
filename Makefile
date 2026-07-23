SHELL := /usr/bin/env bash
PYTHON ?= python3

.PHONY: check install uninstall record-demo

check:
	bash -n bin/tmux-status-observatory tmux-status-observatory.tmux install.sh scripts/record-demo.sh
	$(PYTHON) -m py_compile bin/tmux-status-sweep tests/test_sweep.py
	command -v shellcheck >/dev/null
	shellcheck bin/tmux-status-observatory tmux-status-observatory.tmux install.sh scripts/record-demo.sh tests/test_tmux_binding.sh tests/test_install.sh tests/fixtures/fake-location-curl
	bash tests/test_tmux_binding.sh
	bash tests/test_install.sh
	$(PYTHON) -m unittest discover -s tests -v

install:
	./install.sh

uninstall:
	./install.sh --uninstall

record-demo:
	./scripts/record-demo.sh

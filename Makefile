APP_NAME := Clinder
APP_BUNDLE := dist/$(APP_NAME).app
INSTALLED_BUNDLE := /Applications/$(APP_NAME).app
RUN_SCRIPT := ./script/build_and_run.sh

.PHONY: build run install launch clean

build:
	$(RUN_SCRIPT) stage

run:
	$(RUN_SCRIPT) install-run

install:
	$(RUN_SCRIPT) install

launch:
	open -n "$(INSTALLED_BUNDLE)"

clean:
	rm -rf .build dist

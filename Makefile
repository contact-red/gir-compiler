config ?= debug

PACKAGE := gir-compiler
GET_DEPENDENCIES_WITH := corral fetch
CLEAN_DEPENDENCIES_WITH := corral clean
COMPILE_WITH := corral run -- ponyc

BUILD_DIR ?= build/$(config)
SRC_DIR ?= bin
binary := $(BUILD_DIR)/$(PACKAGE)

ifdef config
	ifeq (,$(filter $(config),debug release))
		$(error Unknown configuration "$(config)")
	endif
endif

ifeq ($(config),release)
	PONYC_FLAGS =
else
	PONYC_FLAGS = --debug
endif

PONYC = $(COMPILE_WITH) $(PONYC_FLAGS) --bin-name $(PACKAGE)

SOURCE_FILES := $(shell find gir scanner planner emitter bin -name '*.pony' 2>/dev/null)
EMBEDDED_SOURCES := $(shell find embedded -name '*.pony' 2>/dev/null)
BAKED := emitter/embedded_resources.pony

all: build

build: $(binary)

$(binary): $(SOURCE_FILES) $(BAKED) | $(BUILD_DIR)
	$(GET_DEPENDENCIES_WITH)
	$(PONYC) -o $(BUILD_DIR) $(SRC_DIR)

$(BAKED): $(EMBEDDED_SOURCES) tools/bake_embedded.sh
	tools/bake_embedded.sh > $(BAKED)

test: build
	@echo "(no automated tests yet — run smoke checks manually)"
	$(binary) --version

clean:
	$(CLEAN_DEPENDENCIES_WITH)
	rm -rf $(BUILD_DIR)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

.PHONY: all build test clean

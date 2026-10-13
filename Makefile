PREFIX ?= $(HOME)/.local
SOURCES := Sources/main.swift Sources/UI.swift Sources/Demo.swift

ask-control: $(SOURCES)
	swiftc -O -o $@ $(SOURCES)

install: ask-control
	install -d $(PREFIX)/bin
	install -m 755 ask-control $(PREFIX)/bin/ask-control

uninstall:
	rm -f $(PREFIX)/bin/ask-control

clean:
	rm -f ask-control

.PHONY: install uninstall clean

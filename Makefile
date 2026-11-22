PREFIX ?= $(HOME)/.local
SOURCES := Sources/main.swift Sources/UI.swift Sources/Demo.swift

ask-control: $(SOURCES)
	swiftc -O -o $@ $(SOURCES)

install: ask-control
	install -d $(PREFIX)/bin
	install -m 755 ask-control $(PREFIX)/bin/ask-control
	@case ":$$PATH:" in *":$(PREFIX)/bin:"*) ;; *) \
	  echo; echo "$(PREFIX)/bin is not on your PATH yet. Add it, then open a new terminal:"; \
	  echo "  echo 'export PATH=\"$(PREFIX)/bin:\$$PATH\"' >> ~/.zshrc"; echo;; esac

test: ask-control
	tests/test.sh ./ask-control

uninstall:
	rm -f $(PREFIX)/bin/ask-control

clean:
	rm -f ask-control

.PHONY: install test uninstall clean

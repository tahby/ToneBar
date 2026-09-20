BUNDLE_ID := com.tonebar.ToneBar
APP := ToneBar.app

.PHONY: app run clean reset-permission

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	cp .build/release/ToneBar $(APP)/Contents/MacOS/ToneBar
	codesign --force --sign - --identifier $(BUNDLE_ID) $(APP)

run: app
	open $(APP)

reset-permission:
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf $(APP) .build

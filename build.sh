#!/bin/bash

set -e

# Compile using standard system paths
mkdir -p ".build/release"

swiftc -swift-version 5 -module-cache-path .build/module-cache Sources/MacbookSibal/*.swift -o ".build/release/MacbookSibal"
echo "Creating App Bundle..."
APP_DIR="PieMenu.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

# Create directories
mkdir -p "${MACOS_DIR}"

# Copy binary
cp ".build/release/MacbookSibal" "${MACOS_DIR}/PieMenu"

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PieMenu</string>
    <key>CFBundleIdentifier</key>
    <string>com.satellite.PieMenu</string>
    <key>CFBundleName</key>
    <string>PieMenu</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Apply ad-hoc code signature to the app bundle to prevent Gatekeeper / AMFI "zsh: killed" errors
echo "Signing App Bundle..."
xattr -cr "${APP_DIR}"
codesign --force --deep --sign - "${APP_DIR}"

echo "Create PKG Installer..."
pkgbuild --component "${APP_DIR}" --install-location "/Applications" "PieMenu.pkg"

echo "Done! PieMenu.app and PieMenu.pkg have been created successfully in $(pwd)"

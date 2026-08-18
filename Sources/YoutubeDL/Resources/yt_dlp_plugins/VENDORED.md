# Vendored yt-dlp plugin

This directory contains the Python sources required by
`yt-dlp-apple-webkit-jsi` 0.1.1.

- Source: https://github.com/grqz/yt-dlp-apple-webkit-jsi
- License: Apache License 2.0 (see `LICENSE`)

Local compatibility patches:

- Resolve Darwin dynamic-loader symbols from the current process instead of
  using `ctypes.util.find_library('dl')`. Python-iOS can otherwise enter the
  Linux lookup path and attempt to spawn `/sbin/ldconfig`, which is unavailable
  to iOS applications.
- Prime the WebKit task generator outside an `assert`. Python-iOS executes
  optimized bytecode, which removes assertions and previously skipped the
  required `send(None)` call.
- Mark Python-managed Objective-C block literals as stack blocks. Retaining
  APIs such as `CFRunLoopPerformBlock` must copy these literals; treating them
  as malloc blocks can preserve an invalid literal and invoke a null callback.

The plugin is bundled as a Swift Package resource so yt-dlp can discover the
Apple WebKit JavaScript interpreter on iOS without a separate plugin install.

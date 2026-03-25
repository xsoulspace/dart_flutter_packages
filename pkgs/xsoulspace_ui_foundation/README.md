# xsoulspace_ui_foundation

Shared UI-focused Flutter helpers, extensions, and pagination utilities.

## Features

- `BuildContext` and `Widget` extensions
- keyboard and device runtime helpers
- utilities for `infinite_scroll_pagination`

## Installation

```yaml
dependencies:
  xsoulspace_ui_foundation: ^0.3.1
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:xsoulspace_ui_foundation/xsoulspace_ui_foundation.dart';

class DemoPage extends StatelessWidget {
  const DemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      body: Center(
        child: Text('Hello', style: context.textTheme.headlineSmall),
      ),
    );
  }
}
```

See `lib/src/utils/infinite_scroll_pagination_utils/README.md` for pagination utilities.

## License

MIT (see [LICENSE](LICENSE)).

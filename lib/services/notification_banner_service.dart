import 'package:flutter/material.dart';

/// Notification banner widget that slides down, stays briefly, then slides up and disappears.
class NotificationBannerWidget extends StatefulWidget {
  final String message;
  final Duration displayDuration;
  final Duration animationDuration;
  final VoidCallback? onDismiss;

  const NotificationBannerWidget({
    super.key,
    required this.message,
    this.displayDuration = const Duration(seconds: 2),
    this.animationDuration = const Duration(milliseconds: 400),
    this.onDismiss,
  });

  @override
  State<NotificationBannerWidget> createState() =>
      _NotificationBannerWidgetState();
}

class _NotificationBannerWidgetState extends State<NotificationBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    // Slide down from top, then slide up and out
    _slideAnimation =
        Tween<Offset>(
          begin: const Offset(0, -1.0),
          end: const Offset(0, 0),
        ).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    // Start slide down animation
    _animationController.forward();

    // Auto-dismiss after display duration
    Future.delayed(
      widget.animationDuration + widget.displayDuration,
      _dismissBanner,
    );
  }

  void _dismissBanner() {
    if (!mounted) return;

    // Reverse animation (slide up)
    _animationController.reverse().then((_) {
      if (mounted) {
        widget.onDismiss?.call();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.teal.shade600, width: 2.5),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.shade300.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Logo + App Name
              Container(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.health_and_safety,
                      color: Colors.teal.shade600,
                      size: 32,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Elder Care',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.87),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Divider
              Container(
                width: 2,
                height: 50,
                color: Colors.teal.shade300.withValues(alpha: 0.3),
              ),
              // Message
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Service to show notification banners
class NotificationBannerService {
  static Future<void> showBanner(
    BuildContext context, {
    required String message,
    Duration displayDuration = const Duration(seconds: 2),
    Duration animationDuration = const Duration(milliseconds: 400),
  }) async {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: NotificationBannerWidget(
            message: message,
            displayDuration: displayDuration,
            animationDuration: animationDuration,
            onDismiss: () {
              overlayEntry.remove();
            },
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
  }

  /// Show success notification
  static Future<void> showSuccess(
    BuildContext context, {
    required String message,
    Duration displayDuration = const Duration(seconds: 2),
  }) async {
    await showBanner(
      context,
      message: message,
      displayDuration: displayDuration,
    );
  }

  /// Show info notification
  static Future<void> showInfo(
    BuildContext context, {
    required String message,
    Duration displayDuration = const Duration(seconds: 2),
  }) async {
    await showBanner(
      context,
      message: message,
      displayDuration: displayDuration,
    );
  }

  /// Show warning notification
  static Future<void> showWarning(
    BuildContext context, {
    required String message,
    Duration displayDuration = const Duration(seconds: 2),
  }) async {
    await showBanner(
      context,
      message: message,
      displayDuration: displayDuration,
    );
  }

  /// Show error notification
  static Future<void> showError(
    BuildContext context, {
    required String message,
    Duration displayDuration = const Duration(seconds: 2),
  }) async {
    await showBanner(
      context,
      message: message,
      displayDuration: displayDuration,
    );
  }
}

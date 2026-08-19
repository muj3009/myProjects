import 'package:flutter/material.dart';

/// A full-width pill CTA with a real gradient fill instead of a flat
/// [ElevatedButton] — used for the Dashboard's Start/Stop Automation button,
/// the two most important taps in the app, so they get a genuinely crafted
/// treatment rather than the same default button style as everything else.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.baseColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onPressed,
        child: Ink(
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(baseColor, Colors.white, 0.16)!, baseColor],
            ),
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: baseColor.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

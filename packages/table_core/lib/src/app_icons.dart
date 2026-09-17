import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// Ikona z pliku SVG. Odpowiednik [IconData] dla ikon Phosphor.
@immutable
class AppIconData {
  const AppIconData(this.asset);

  final String asset;
}

/// Rysuje [AppIconData] jak [Icon]: rozmiar i kolor domyślnie z [IconTheme],
/// więc ikony w przyciskach i dolnym menu dostają kolory z motywu.
class Glyph extends StatelessWidget {
  const Glyph(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final AppIconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final color = this.color ?? theme.color ?? const Color(0xFF000000);
    final opacity = theme.opacity ?? 1;
    final svg = SvgPicture.asset(
      icon.asset,
      package: 'table_core',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color.withValues(alpha: color.a * opacity),
        BlendMode.srcIn,
      ),
      excludeFromSemantics: true,
    );
    // Jak w [Icon]: Center pozwala zachować rozmiar ikony, gdy rodzic wymusza
    // większy obszar, na przykład kafelek w ustawieniach.
    final box = SizedBox(
      width: size,
      height: size,
      child: Center(child: svg),
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: box)
        : Semantics(label: label, child: box);
  }
}

/// Ikony Phosphor z Iconify, pobrane skillem better-icons do assets/icons.
/// Nowa ikona: `npx better-icons get ph:<nazwa> > assets/icons/<nazwa>.svg` i wpis poniżej.
abstract final class AppIcons {
  static const alarm = AppIconData('assets/icons/alarm.svg');
  static const armchair = AppIconData('assets/icons/armchair.svg');
  static const arrowLeft = AppIconData('assets/icons/arrow-left.svg');
  static const arrowUpRight = AppIconData('assets/icons/arrow-up-right.svg');
  static const arrowsClockwise = AppIconData('assets/icons/arrows-clockwise.svg');
  static const bell = AppIconData('assets/icons/bell.svg');
  static const bookOpen = AppIconData('assets/icons/book-open-text.svg');
  static const bowlFood = AppIconData('assets/icons/bowl-food.svg');
  static const bug = AppIconData('assets/icons/bug.svg');
  static const calendar = AppIconData('assets/icons/calendar-blank.svg');
  static const calendarCheck = AppIconData('assets/icons/calendar-check.svg');
  static const calendarDots = AppIconData('assets/icons/calendar-dots.svg');
  static const calendarDotsFill = AppIconData('assets/icons/calendar-dots-fill.svg');
  static const calendarPlus = AppIconData('assets/icons/calendar-plus.svg');
  static const calendarX = AppIconData('assets/icons/calendar-x.svg');
  static const caretDown = AppIconData('assets/icons/caret-down.svg');
  static const caretLeft = AppIconData('assets/icons/caret-left.svg');
  static const caretUp = AppIconData('assets/icons/caret-up.svg');
  static const caretRight = AppIconData('assets/icons/caret-right.svg');
  static const chartBar = AppIconData('assets/icons/chart-bar.svg');
  static const chatCircle = AppIconData('assets/icons/chat-circle-text.svg');
  static const chatText = AppIconData('assets/icons/chat-text.svg');
  static const check = AppIconData('assets/icons/check.svg');
  static const checkCircle = AppIconData('assets/icons/check-circle.svg');
  static const circle = AppIconData('assets/icons/circle.svg');
  static const circleHalf = AppIconData('assets/icons/circle-half.svg');
  static const circleHalfTilt = AppIconData('assets/icons/circle-half-tilt.svg');
  static const clock = AppIconData('assets/icons/clock.svg');
  static const close = AppIconData('assets/icons/x.svg');
  static const compass = AppIconData('assets/icons/compass.svg');
  static const compassFill = AppIconData('assets/icons/compass-fill.svg');
  static const confetti = AppIconData('assets/icons/confetti.svg');
  static const copy = AppIconData('assets/icons/copy.svg');
  static const deviceMobile = AppIconData('assets/icons/device-mobile.svg');
  static const doorOpen = AppIconData('assets/icons/door-open.svg');
  static const envelope = AppIconData('assets/icons/envelope-simple.svg');
  static const dotsVertical = AppIconData('assets/icons/dots-three-vertical.svg');
  static const eye = AppIconData('assets/icons/eye.svg');
  static const eyeSlash = AppIconData('assets/icons/eye-slash.svg');
  static const forkKnife = AppIconData('assets/icons/fork-knife.svg');
  static const funnel = AppIconData('assets/icons/funnel.svg');
  static const gear = AppIconData('assets/icons/gear-six.svg');
  static const gearFill = AppIconData('assets/icons/gear-six-fill.svg');
  static const gpsSlash = AppIconData('assets/icons/gps-slash.svg');
  static const identification = AppIconData('assets/icons/identification-card.svg');
  static const list = AppIconData('assets/icons/list-bullets.svg');
  static const lock = AppIconData('assets/icons/lock-simple.svg');
  static const mapPin = AppIconData('assets/icons/map-pin.svg');
  static const megaphone = AppIconData('assets/icons/megaphone.svg');
  static const minus = AppIconData('assets/icons/minus.svg');
  static const moon = AppIconData('assets/icons/moon.svg');
  static const move = AppIconData('assets/icons/arrows-out-cardinal.svg');
  static const navigation = AppIconData('assets/icons/navigation-arrow.svg');
  static const notePencil = AppIconData('assets/icons/note-pencil.svg');
  static const password = AppIconData('assets/icons/password.svg');
  static const pencil = AppIconData('assets/icons/pencil-simple.svg');
  static const phone = AppIconData('assets/icons/phone.svg');
  static const phoneSwap = AppIconData('assets/icons/swap.svg');
  static const plus = AppIconData('assets/icons/plus.svg');
  static const prohibit = AppIconData('assets/icons/prohibit.svg');
  static const question = AppIconData('assets/icons/question.svg');
  static const rectangle = AppIconData('assets/icons/rectangle.svg');
  static const refresh = AppIconData('assets/icons/arrow-clockwise.svg');
  static const search = AppIconData('assets/icons/magnifying-glass.svg');
  static const signOut = AppIconData('assets/icons/sign-out.svg');
  static const sliders = AppIconData('assets/icons/sliders-horizontal.svg');
  static const sort = AppIconData('assets/icons/arrows-down-up.svg');
  static const squaresFour = AppIconData('assets/icons/squares-four.svg');
  static const star = AppIconData('assets/icons/star.svg');
  static const starFill = AppIconData('assets/icons/star-fill.svg');
  static const storefront = AppIconData('assets/icons/storefront.svg');
  static const sun = AppIconData('assets/icons/sun.svg');
  static const timer = AppIconData('assets/icons/timer.svg');
  static const trash = AppIconData('assets/icons/trash.svg');
  static const undo = AppIconData('assets/icons/arrow-counter-clockwise.svg');
  static const userCheck = AppIconData('assets/icons/user-check.svg');
  static const userGear = AppIconData('assets/icons/user-gear.svg');
  static const userMinus = AppIconData('assets/icons/user-minus.svg');
  static const users = AppIconData('assets/icons/users.svg');
  static const warning = AppIconData('assets/icons/warning-circle.svg');
  static const wifiOff = AppIconData('assets/icons/wifi-slash.svg');
  static const wrench = AppIconData('assets/icons/wrench.svg');
}

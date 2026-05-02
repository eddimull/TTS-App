import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/shared/widgets/band_avatar.dart';

Widget _wrap(Widget child) => CupertinoApp(home: Center(child: child));

void main() {
  group('BandAvatar.forBand', () {
    testWidgets('renders fallback initial when logoUrl is null', (tester) async {
      const band = BandSummary(
        id: 1,
        name: 'The Stooges',
        isOwner: true,
      );

      await tester.pumpWidget(_wrap(const BandAvatar.forBand(band: band)));

      expect(find.text('T'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('uses CachedNetworkImage when logoUrl is present',
        (tester) async {
      const band = BandSummary(
        id: 2,
        name: 'Anything',
        isOwner: false,
        logoUrl: 'https://example.com/logo.png',
      );

      await tester.pumpWidget(_wrap(const BandAvatar.forBand(band: band)));

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.text('A'), findsNothing);
    });

    testWidgets('uppercases the initial', (tester) async {
      const band = BandSummary(id: 3, name: 'awesome band', isOwner: false);

      await tester.pumpWidget(_wrap(const BandAvatar.forBand(band: band)));

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('renders "?" for empty band name', (tester) async {
      const band = BandSummary(id: 4, name: '', isOwner: false);

      await tester.pumpWidget(_wrap(const BandAvatar.forBand(band: band)));

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('respects size param', (tester) async {
      const band = BandSummary(id: 5, name: 'Big', isOwner: false);

      await tester.pumpWidget(_wrap(
          const BandAvatar.forBand(band: band, size: 40)));

      expect(tester.getSize(find.byType(Container).first),
          const Size(40, 40));
    });
  });

  group('BandAvatar.forUser', () {
    testWidgets('renders user initial when imageUrl is null', (tester) async {
      await tester.pumpWidget(_wrap(
          const BandAvatar.forUser(imageUrl: null, name: 'Eddie')));

      expect(find.text('E'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('uses CachedNetworkImage when imageUrl is present',
        (tester) async {
      await tester.pumpWidget(_wrap(
          const BandAvatar.forUser(
        imageUrl: 'https://example.com/me.png',
        name: 'Eddie',
      )));

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('falls back to "?" for empty user name', (tester) async {
      await tester.pumpWidget(_wrap(
          const BandAvatar.forUser(imageUrl: null, name: '')));

      expect(find.text('?'), findsOneWidget);
    });
  });
}

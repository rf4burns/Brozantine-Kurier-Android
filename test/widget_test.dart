import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurier_web/app/app.dart';
import 'package:kurier_web/app/breakpoints.dart';
import 'package:kurier_web/app/theme.dart';
import 'package:kurier_web/protocol/config.dart';
import 'package:kurier_web/protocol/models.dart';
import 'package:kurier_web/protocol/permissions.dart';
import 'package:kurier_web/protocol/sounds.dart';
import 'package:kurier_web/protocol/voice_stats.dart';
import 'package:kurier_web/session/hosts_store.dart';
import 'package:kurier_web/session/session_controller.dart';
import 'package:kurier_web/ui/attachment_media.dart';
import 'package:kurier_web/ui/home_shell.dart';
import 'package:kurier_web/ui/member_list.dart';
import 'package:kurier_web/ui/message_embeds.dart';
import 'package:kurier_web/ui/gif_favourite_star.dart';
import 'package:kurier_web/ui/image_fullscreen.dart';
import 'package:kurier_web/ui/image_lightbox.dart';
import 'package:kurier_web/ui/panel_resize_handle.dart';
import 'package:kurier_web/ui/profile_card.dart';
import 'package:kurier_web/ui/settings_chrome.dart';
import 'package:kurier_web/ui/shared.dart';
import 'package:kurier_web/ui/voice_stage.dart';
import 'package:shared_preferences/shared_preferences.dart';

SessionController _loginSession({ServerInfo? info}) {
  final s = SessionController();
  s.phase = SessionPhase.login;
  s.activeHost = AppConfig.defaultHost;
  s.info = info;
  return s;
}

SessionController _readySession({
  int? selectedChannelId,
  List<KurierMessage>? messages,
}) {
  final s = SessionController();
  s.phase = SessionPhase.ready;
  s.serverName = 'Test Server';
  s.ownUserId = 1;
  s.users[1] = KurierUser(id: 1, name: 'Ada', status: 'online');
  s.users[2] = KurierUser(id: 2, name: 'Gordon', status: 'online');
  s.channels[10] = KurierChannel(
    id: 10,
    type: 'TEXT',
    name: 'general',
    position: 0,
  );
  s.selectedChannelId = selectedChannelId;
  s.messages[10] =
      messages ??
      [
        KurierMessage(
          id: 1,
          channelId: 10,
          createdAt: 0,
          content: '<p>hello overlay</p>',
          userId: 1,
        ),
        KurierMessage(
          id: 2,
          channelId: 10,
          createdAt: 1,
          content: '<p>yes i can</p>',
          userId: 1,
        ),
        KurierMessage(
          id: 3,
          channelId: 10,
          createdAt: 2,
          content: '<p>i am m</p>',
          userId: 1,
        ),
      ];
  return s;
}

void _grantOwner(SessionController s) {
  s.roles[AppConfig.ownerRoleId] = KurierRole(
    id: AppConfig.ownerRoleId,
    name: 'Owner',
    color: '#FFD700',
    position: 100,
    hoist: true,
    isDefault: false,
    isPersistent: true,
    permissions: Permission.all,
  );
  s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
}

Widget _app(SessionController session) {
  return ProviderScope(
    overrides: [sessionProvider.overrideWith((ref) => session)],
    child: const KurierApp(),
  );
}

KurierFile _mediaFile({
  int id = 42,
  String name = 'clip.mp4',
  String originalName = 'SNEEDING_HAS_STARTED_1.mp4',
  String mimeType = 'video/mp4',
  String extension = 'mp4',
}) {
  return KurierFile(
    id: id,
    name: name,
    originalName: originalName,
    md5: '',
    userId: 1,
    size: 1,
    mimeType: mimeType,
    extension: extension,
    createdAt: 0,
  );
}

void main() {
  setUp(() {
    youtubeOEmbedLookup = (_) async => null;
    resetImageFullscreen();
  });
  tearDown(() {
    youtubeOEmbedLookup = null;
    resetImageFullscreen();
  });
  testWidgets('login screen shows connect controls', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(_loginSession()));
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Connect'), findsWidgets);
    expect(find.text('Identity'), findsOneWidget);
    expect(find.text('Login automatically'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text(AppConfig.defaultHost), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Kurier',
    );
  });

  testWidgets('login screen shows probed server branding', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        _loginSession(
          info: ServerInfo(
            serverId: '1',
            name: 'Holy Broman Empire',
            version: '0.0.40',
            allowNewUsers: true,
            description:
                'Welcome to the Holy Broman Empire, all is welcome! You will NOT lose your roles randomly!!!!',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Holy Broman Empire'), findsOneWidget);
    expect(find.textContaining('all is welcome'), findsOneWidget);
    expect(find.text('v0.0.40'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Holy Broman Empire - Kurier',
    );
  });

  testWidgets('phone home shows channel list', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession()));
    await tester.pump();
    expect(find.text('Servers'), findsNothing);
    expect(find.text('Chats'), findsNothing);
    expect(find.text('You'), findsNothing);
    expect(find.text('general'), findsWidgets);
    expect(find.text('Test Server'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Test Server - Kurier',
    );
  });

  testWidgets('phone swipe right from DMs returns to last text channel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    await s.selectChannel(10);

    await tester.pumpWidget(_app(s));
    await tester.pump();
    expect(find.text('hello overlay'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    expect(find.text('Direct Messages'), findsNothing);

    await tester.tap(find.byIcon(Icons.forum));
    await tester.pump();
    expect(find.text('Direct Messages'), findsOneWidget);
    expect(find.text('hello overlay'), findsNothing);

    await tester.fling(find.text('Direct Messages'), const Offset(300, 0), 800);
    await tester.pumpAndSettle();
    expect(s.showingDms, isFalse);
    expect(s.selectedChannelId, 10);
    expect(find.text('hello overlay'), findsOneWidget);
    expect(find.text('Direct Messages'), findsNothing);
  });

  testWidgets('desktop chat shows message and member list', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();
    expect(find.text('hello overlay'), findsOneWidget);
    expect(find.text('yes i can'), findsOneWidget);
    expect(find.text('i am m'), findsOneWidget);
    expect(find.text('Ada'), findsWidgets);
    expect(find.text('Gordon'), findsOneWidget);
    expect(find.text('Servers'), findsNothing);
  });

  testWidgets('chat messages stack like vanilla groups', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();

    final hello = tester.getRect(find.text('hello overlay'));
    final yes = tester.getRect(find.text('yes i can'));
    final iam = tester.getRect(find.text('i am m'));
    final author = tester.getRect(find.byKey(const ValueKey('msg-author-1')));

    expect(hello.top - author.bottom, lessThan(4));
    expect(yes.top - hello.bottom, lessThan(8));
    expect(iam.top - yes.bottom, lessThan(8));
    expect(hello.left, closeTo(author.left, 1));
    expect(yes.left, closeTo(hello.left, 1));
  });

  testWidgets('detached history shows a jump-to-present banner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.detachedChannels.add(10);

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text("You're viewing older messages"), findsOneWidget);
    expect(find.text('Jump to present'), findsWidgets);
  });

  testWidgets('system messages show the server bot name', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(
      selectedChannelId: 10,
      messages: [
        KurierMessage(
          id: 40,
          channelId: 10,
          createdAt: 0,
          content:
              '<p>Hey <span data-type="mention">@Ada</span> Welcome to the Holy Broman Empire</p>',
        ),
      ],
    );
    s.serverName = 'Holy Broman Empire';

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Holy Broman Empire Bot'), findsOneWidget);
    expect(find.text('Unknown user'), findsNothing);
    expect(find.text('BOT'), findsNothing);
  });

  testWidgets('message mentions use the live nickname', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(
      selectedChannelId: 10,
      messages: [
        KurierMessage(
          id: 40,
          channelId: 10,
          createdAt: 0,
          content:
              '<p>Hey <span data-type="mention" data-user-id="1">@Ada</span> Welcome to the Holy Broman Empire</p>',
        ),
      ],
    );
    s.serverName = 'Holy Broman Empire';

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.textContaining('@Ada'), findsOneWidget);
    expect(find.textContaining('@Gordon'), findsNothing);

    s.users[1] = s.users[1]!.copyWith(nickname: 'Gordon');
    s.refresh();
    await tester.pump();

    expect(find.textContaining('@Gordon'), findsOneWidget);
    expect(find.textContaining('@Ada'), findsNothing);
  });

  testWidgets('plugin messages show plugin name and BOT badge', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(
      selectedChannelId: 10,
      messages: [
        KurierMessage(
          id: 41,
          channelId: 10,
          createdAt: 0,
          content: '<p>plugin hello</p>',
          pluginId: 'welcome-bot',
        ),
      ],
    );
    s.pluginsMetadata = [
      {'pluginId': 'welcome-bot', 'name': 'Welcome Plugin'},
    ];

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Welcome Plugin'), findsOneWidget);
    expect(find.text('BOT'), findsOneWidget);
    expect(find.text('Unknown user'), findsNothing);
  });

  testWidgets('long-pressing a reaction opens a Discord-style viewer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(
      selectedChannelId: 10,
      messages: [
        KurierMessage(
          id: 1,
          channelId: 10,
          createdAt: 0,
          content: '<p>reacted</p>',
          userId: 1,
          reactions: [
            MessageReaction(messageId: 1, emoji: 'heart', userId: 1),
            MessageReaction(messageId: 1, emoji: 'heart', userId: 2),
            MessageReaction(messageId: 1, emoji: 'joy', userId: 3),
          ],
        ),
      ],
    );
    s.users[2] = KurierUser(
      id: 2,
      name: 'dragendave',
      nickname: 'Gordon',
      status: 'online',
    );
    s.users[3] = KurierUser(
      id: 3,
      name: 'synkro',
      nickname: 'Synkro',
      status: 'online',
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();

    await tester.longPress(find.byKey(const ValueKey('reaction-1-heart')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('reactions-viewer')), findsOneWidget);
    expect(find.text('Reactions'), findsOneWidget);
    expect(find.byKey(const ValueKey('reactions-user-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('reactions-user-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('reactions-user-3')), findsNothing);
    expect(find.text('dragendave'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reactions-tab-joy')));
    await tester.pump();

    expect(find.byKey(const ValueKey('reactions-user-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('reactions-user-1')), findsNothing);
    expect(find.byKey(const ValueKey('reactions-user-2')), findsNothing);
  });

  testWidgets('desktop channel toolbar is right-aligned in the header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();

    final pin = tester.getRect(find.byIcon(Icons.push_pin_outlined));
    final mentions = tester.getRect(find.byIcon(Icons.alternate_email));
    final search = tester.getRect(find.text('Search for content...'));
    final members = tester.getRect(find.text('Members — 2'));

    expect(mentions.left, greaterThan(pin.right - 1));
    expect(search.left, greaterThan(mentions.right - 1));
    expect(members.left, greaterThan(search.right));
    expect(members.left - pin.left, lessThan(320));
    expect(pin.left, greaterThan(700));
  });

  testWidgets('desktop channel sidebar can be resized by dragging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();

    expect(tester.getSize(find.byType(ChannelSidebar)).width, 240);

    await tester.drag(
      find.byKey(PanelResizeHandle.channelsKey),
      const Offset(80, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final width = tester.getSize(find.byType(ChannelSidebar)).width;
    expect(width, greaterThan(280));
    expect(width, lessThanOrEqualTo(320));
  });

  testWidgets('desktop members panel can be resized by dragging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();

    expect(tester.getSize(find.byType(MemberList)).width, 240);

    await tester.drag(
      find.byKey(PanelResizeHandle.membersKey),
      const Offset(-50, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final width = tester.getSize(find.byType(MemberList)).width;
    expect(width, greaterThan(250));
    expect(width, lessThanOrEqualTo(290));
  });

  testWidgets('pins button opens a native-style popover', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.pinned = [
      KurierMessage(
        id: 1,
        channelId: 10,
        createdAt: 0,
        content: '<p>hello overlay</p>',
        userId: 1,
        pinned: true,
        pinnedBy: 1,
        pinnedAt: DateTime(2026, 8, 6, 21, 42, 2).millisecondsSinceEpoch,
      ),
    ];

    await tester.pumpWidget(_app(s));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.push_pin_outlined));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pins-popover')), findsOneWidget);
    expect(find.text('Pinned messages'), findsWidgets);
    expect(find.text('Pinned by Ada'), findsOneWidget);
    expect(find.byTooltip('Scroll to message'), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-jump-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pin-jump-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pins-popover')), findsNothing);
    expect(find.byKey(const ValueKey('msg-author-1')), findsOneWidget);
  });

  testWidgets('search dialog lists filter operators and user values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();
    await tester.tap(find.text('Search for content...'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('from:'), findsOneWidget);
    expect(find.text('Messages from a user'), findsOneWidget);
    expect(find.text('mentions:'), findsOneWidget);
    expect(find.text('in:'), findsOneWidget);
    expect(find.text('has:'), findsOneWidget);
    expect(find.text('before:'), findsOneWidget);
    expect(find.text('after:'), findsOneWidget);
    expect(find.text('during:'), findsOneWidget);
    expect(find.text('pinned:'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('search-op-from')));
    await tester.pump();

    expect(find.byKey(const ValueKey('search-op-from-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-op-from-2')), findsOneWidget);
  });

  testWidgets('mentions dialog lists messages that mention you', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.mentionMessages = [
      KurierMessage(
        id: 99,
        channelId: 10,
        createdAt: DateTime.now().millisecondsSinceEpoch - 2 * 60 * 60 * 1000,
        content:
            '<p>hey <span data-type="mention" data-user-id="1">@Ada</span> look</p>',
        userId: 2,
      ),
    ];

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mentions-button')));
    await tester.pumpAndSettle();

    expect(find.text('Mentions'), findsOneWidget);
    expect(
      find.text('Messages that mention you in this server.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mention-result-99')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Gordon')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.textContaining('#general'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.textContaining('hey @Ada look'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('mentions button shows a red unread badge', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.unreadMentionIds.add(99);

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.byKey(const ValueKey('mentions-unread-badge')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mentions-unread-badge')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('mentions-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mentions-unread-badge')), findsNothing);
    expect(find.text('No mentions yet'), findsOneWidget);
  });

  testWidgets('message bar is a unified rounded composer', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = KurierUser(
      id: 1,
      name: 'Ada',
      status: 'online',
      roleIds: [AppConfig.ownerRoleId],
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Message #general'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsNothing);
    expect(find.byIcon(Icons.add_circle), findsNothing);
    expect(find.byIcon(Icons.card_giftcard_outlined), findsNothing);
    expect(find.byIcon(Icons.gif_box_outlined), findsOneWidget);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsNothing);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsOneWidget);

    final field = tester.getRect(find.byType(TextField));
    final clip = tester.getRect(find.byIcon(Icons.attach_file));
    final emoji = tester.getRect(find.byIcon(Icons.emoji_emotions_outlined));
    expect(clip.left, greaterThan(field.right - 1));
    expect(emoji.left, greaterThan(field.right - 1));
    expect((emoji.center.dy - field.center.dy).abs(), lessThan(12));
  });

  testWidgets('shift+enter inserts a paragraph break in the composer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();

    final field = find.byType(TextField);
    await tester.enterText(field, 'hello');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    expect(tester.widget<TextField>(field).controller!.text, 'hello\n');

    await tester.enterText(field, 'hello\n');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    expect(tester.widget<TextField>(field).controller!.text, 'hello\n\n');
  });

  testWidgets('enter sends the composed message', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();

    final field = find.byType(TextField);
    await tester.enterText(field, 'hello');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
  });

  testWidgets('composer caps messages at 4000 characters', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();

    final fieldFinder = find.byType(TextField);
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.maxLength, AppConfig.maxMessageLength);
    expect(field.maxLines, 8);

    await tester.enterText(fieldFinder, 'a' * 5000);
    await tester.pump();
    expect(
      tester.widget<TextField>(fieldFinder).controller!.text.length,
      AppConfig.maxMessageLength,
    );
  });

  testWidgets('desktop compose emoji opens the Discord picker dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Search all emojis…'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('phone compose emoji opens the picker in a bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Search all emojis…'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('desktop compose GIF opens the Discord picker dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.gif_box_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Search GIFs'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('GIF picker asks for a KLIPY key off Brozantine hosts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final s = _readySession(selectedChannelId: 10);
    s.activeHost = 'example.com';
    await s.store.load();

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.gif_box_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Set a KLIPY API key in Settings to search GIFs'),
      findsOneWidget,
    );
    expect(find.text('No GIFs found'), findsNothing);
  });

  testWidgets('phone compose GIF opens the picker in a bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.gif_box_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Search GIFs'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('tapping a voice occupant opens profile, not the channel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession();
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );
    s.voiceMap[20] = {2: VoiceUserState(micMuted: true)};

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('public!!'), findsOneWidget);
    expect(find.text('Gordon'), findsOneWidget);
    expect(s.selectedChannelId, isNull);
    expect(s.profileUser, isNull);

    await tester.tap(find.text('Gordon'));
    await tester.pump();

    expect(s.selectedChannelId, isNull);
    expect(s.profileUser?.id, 2);
    expect(find.text('Message'), findsOneWidget);

    s.closeOverlay();
    await tester.pump();
    expect(s.profileUser, isNull);

    await tester.tap(find.text('public!!'));
    await tester.pump();
    expect(s.selectedChannelId, 20);
    expect(s.profileUser, isNull);

    await tester.tap(find.text('Gordon'));
    await tester.pump();
    expect(s.profileUser?.id, 2);
    expect(s.selectedChannelId, 20);
  });

  testWidgets('voice occupants sit under the channel name with elapsed time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now().millisecondsSinceEpoch;
    final s = _readySession(selectedChannelId: 10);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );
    s.occupiedSince[20] = now - 125000;
    s.voiceMap[20] = {
      2: VoiceUserState(micMuted: true, joinedAt: now - 115000),
    };

    await tester.pumpWidget(_app(s));
    await tester.pump();

    final channel = tester.getRect(find.text('public!!'));
    final occupant = tester.getRect(find.text('Gordon').first);
    expect(occupant.left, greaterThan(channel.left + 12));
    expect(occupant.top, greaterThan(channel.bottom));
    expect(find.text('2:05'), findsOneWidget);
    expect(find.text('1:55'), findsOneWidget);
    expect(find.byIcon(Icons.mic_off), findsWidgets);
  });

  testWidgets('voice channel status sits under the name above occupants', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
      topic: 'Playing games',
    );
    s.voiceMap[20] = {2: VoiceUserState(micMuted: true)};

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(ChannelSidebar),
        matching: find.text('Playing games'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(VoiceStage),
        matching: find.text('Playing games'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(VoiceStatusText),
        matching: find.byType(UserAvatar),
      ),
      findsNothing,
    );

    final channel = tester.getRect(
      find.descendant(
        of: find.byType(ChannelSidebar),
        matching: find.text('public!!'),
      ),
    );
    final status = tester.getRect(
      find.descendant(
        of: find.byType(ChannelSidebar),
        matching: find.text('Playing games'),
      ),
    );
    final occupant = tester.getRect(
      find.descendant(
        of: find.byType(ChannelSidebar),
        matching: find.text('Gordon'),
      ),
    );
    expect(status.top, greaterThan(channel.top));
    expect(occupant.top, greaterThan(status.bottom));
  });

  testWidgets('phone shows voice channel status in the sidebar and stage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession();
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
      topic: 'Playing games',
    );
    s.voiceMap[20] = {2: VoiceUserState()};

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.byType(ChannelSidebar), findsOneWidget);
    expect(find.text('Playing games'), findsOneWidget);
    expect(find.byType(VoiceStage), findsNothing);

    await tester.tap(find.text('public!!'));
    await tester.pump();

    expect(find.byType(VoiceStage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(VoiceStage),
        matching: find.text('Playing games'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('channel bar rows match vanilla spacing', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.categories[1] = KurierCategory(id: 1, name: 'info', position: 0);
    s.channels[10] = KurierChannel(
      id: 10,
      type: 'TEXT',
      name: 'general',
      position: 0,
      categoryId: 1,
    );
    s.channels[11] = KurierChannel(
      id: 11,
      type: 'TEXT',
      name: 'announcements',
      position: 1,
      categoryId: 1,
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();

    final general = tester.getRect(find.text('general').first);
    final announcements = tester.getRect(find.text('announcements'));
    final gap = announcements.top - general.bottom;
    expect(gap, greaterThanOrEqualTo(12));
    expect(gap, lessThan(24));

    final category = tester.getRect(find.text('INFO'));
    expect(general.top - category.bottom, greaterThanOrEqualTo(4));
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.tag), findsWidgets);
  });

  testWidgets('sidebar hides private categories without VIEW_CHANNEL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: const [2]);
    s.roles[2] = KurierRole(
      id: 2,
      name: 'Member',
      color: '#888888',
      position: 0,
      hoist: false,
      isDefault: true,
      isPersistent: true,
    );
    s.categories[1] = KurierCategory(id: 1, name: 'info', position: 0);
    s.categories[2] = KurierCategory(id: 2, name: 'inner gates', position: 1);
    s.categories[3] = KurierCategory(id: 3, name: 'empty', position: 2);
    s.channels[10] = KurierChannel(
      id: 10,
      type: 'TEXT',
      name: 'announcements',
      position: 0,
      categoryId: 1,
    );
    s.channels[11] = KurierChannel(
      id: 11,
      type: 'TEXT',
      name: 'secret-ops',
      position: 0,
      categoryId: 2,
      private: true,
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('INFO'), findsOneWidget);
    expect(find.text('announcements'), findsWidgets);
    expect(find.text('INNER GATES'), findsNothing);
    expect(find.text('EMPTY'), findsNothing);
    expect(find.text('secret-ops'), findsNothing);
  });

  testWidgets('sidebar shows private category when VIEW_CHANNEL is granted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: const [2]);
    s.roles[2] = KurierRole(
      id: 2,
      name: 'Member',
      color: '#888888',
      position: 0,
      hoist: false,
      isDefault: true,
      isPersistent: true,
    );
    s.categories[2] = KurierCategory(id: 2, name: 'inner gates', position: 1);
    s.channels[11] = KurierChannel(
      id: 11,
      type: 'TEXT',
      name: 'secret-ops',
      position: 0,
      categoryId: 2,
      private: true,
    );
    s.channelPerms['11'] = ChannelPerms({ChannelPermission.viewChannel: true});

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('INNER GATES'), findsOneWidget);
    expect(find.text('secret-ops'), findsOneWidget);
  });

  test('formatElapsed matches vanilla timers', () {
    expect(formatElapsed(0, 0), '0:00');
    expect(formatElapsed(0, 5000), '0:05');
    expect(formatElapsed(0, 125000), '2:05');
    expect(formatElapsed(0, 3723000), '1:02:03');
  });

  testWidgets('sidebar shows speaking ring on talking voice occupant', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'voice',
      position: 1,
    );
    s.voiceMap[20] = {
      1: VoiceUserState(),
      2: VoiceUserState(),
      3: VoiceUserState(micMuted: true),
    };
    s.users[3] = KurierUser(id: 3, name: 'Muted', status: 'online');
    s.speaking[2] = 2;
    s.speaking[3] = 2;

    await tester.pumpWidget(_app(s));
    await tester.pump();
    expect(find.text('voice'), findsWidgets);
    expect(find.text('Gordon'), findsWidgets);
    expect(find.byKey(const ValueKey('speaking-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('speaking-1')), findsNothing);
    expect(find.byKey(const ValueKey('speaking-3')), findsNothing);
  });

  testWidgets('screen stream audio starts muted and can be unmuted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );
    s.voiceMap[20] = {2: VoiceUserState(sharingScreen: true)};
    s.consumerKeys['2:screen_audio'] = '2:screen_audio';
    s.volumes['2:screen_audio'] = 0;
    s.watchingStreams.add('2:screen');
    s.connectedVoiceChannelId = 20;

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(s.volumes['2:screen_audio'], 0);

    await tester.tap(find.byIcon(Icons.volume_off));
    await tester.pump();

    expect(find.byIcon(Icons.volume_off), findsNothing);
    expect(s.volumes['2:screen_audio'], 1);
    expect(s.profileUser, isNull);
  });

  testWidgets('music-bot audio starts muted and can be unmuted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );
    s.externalStreams[20] = [
      ExternalStream(
        title: 'Music Bot',
        key: 'music-bot',
        pluginId: 'music-bot',
        streamId: 9,
      ),
    ];
    s.consumerKeys['9:external_audio'] = '9:external_audio';
    s.volumes['9:external_audio'] = 0;
    s.watchingStreams.add('9:external');
    s.connectedVoiceChannelId = 20;

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(s.volumes['9:external_audio'], 0);

    await tester.tap(find.byIcon(Icons.volume_off));
    await tester.pump();

    expect(find.byIcon(Icons.volume_off), findsNothing);
    expect(s.volumes['9:external_audio'], 1);
    expect(s.profileUser, isNull);
  });

  testWidgets('screen share shows Watch Stream until the user opts in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );
    s.voiceMap[20] = {2: VoiceUserState(sharingScreen: true)};
    s.connectedVoiceChannelId = 20;
    s.voiceState = 'connected';

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Watch Stream'), findsOneWidget);
    expect(find.byKey(const ValueKey('watch-stream-2')), findsOneWidget);

    await tester.tap(find.text('Watch Stream'));
    await tester.pump();

    expect(find.text('Watch Stream'), findsNothing);
    expect(s.watchingStreams.contains('2:screen'), isTrue);
    expect(find.byKey(const ValueKey('stop-watching-2')), findsOneWidget);
  });

  testWidgets('Watch Stream is disabled unless connected to that channel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );
    s.voiceMap[20] = {2: VoiceUserState(sharingScreen: true)};

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.byKey(const ValueKey('watch-stream-2')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('watch-stream-2')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('watch-stream-2')));
    await tester.pump();
    await tester.pump();
    expect(s.watchingStreams.contains('2:screen'), isFalse);
    expect(find.text("You don't have permission to do that."), findsOneWidget);

    s.connectedVoiceChannelId = 21;
    s.voiceState = 'connected';
    s.notifyListeners();
    await tester.pump();

    await tester.tap(find.text('Watch Stream'));
    await tester.pump();
    await tester.pump();
    expect(s.watchingStreams.contains('2:screen'), isFalse);
    expect(find.text("You don't have permission to do that."), findsWidgets);
  });

  testWidgets('join voice without permission shows an error', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();

    await tester.tap(find.text('Join Voice'));
    await tester.pump();
    await tester.pump();
    expect(s.voiceState, 'idle');
    expect(s.connectedVoiceChannelId, isNull);
    expect(find.text("You don't have permission to do that."), findsOneWidget);
  });

  testWidgets('watched stream can fill the occupant area and show stats', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );
    s.voiceMap[20] = {
      1: VoiceUserState(),
      2: VoiceUserState(sharingScreen: true),
    };
    s.connectedVoiceChannelId = 20;
    s.voiceState = 'connected';

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(
      find.descendant(of: find.byType(VoiceStage), matching: find.text('Ada')),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('fullscreen-stream-2')), findsNothing);

    await tester.tap(find.text('Watch Stream'));
    await tester.pump();

    expect(find.text('0 FPS'), findsOneWidget);
    expect(find.text('0 KB/s'), findsOneWidget);
    expect(find.byKey(const ValueKey('fullscreen-stream-2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fullscreen-stream-2')));
    await tester.pump();

    expect(
      find.descendant(of: find.byType(VoiceStage), matching: find.text('Ada')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('exit-fullscreen-stream-2')),
      findsOneWidget,
    );
    expect(find.text('0 FPS'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('exit-fullscreen-stream-2')));
    await tester.pump();

    expect(
      find.descendant(of: find.byType(VoiceStage), matching: find.text('Ada')),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('fullscreen-stream-2')), findsOneWidget);
  });

  testWidgets('stop watching exits stream fullscreen', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );
    s.voiceMap[20] = {
      1: VoiceUserState(),
      2: VoiceUserState(sharingScreen: true),
    };
    s.connectedVoiceChannelId = 20;
    s.voiceState = 'connected';

    await tester.pumpWidget(_app(s));
    await tester.pump();

    await tester.tap(find.text('Watch Stream'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fullscreen-stream-2')));
    await tester.pump();

    expect(
      find.descendant(of: find.byType(VoiceStage), matching: find.text('Ada')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('stop-watching-2')));
    await tester.pump();

    expect(find.text('Watch Stream'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(VoiceStage), matching: find.text('Ada')),
      findsWidgets,
    );
    expect(
      find.byKey(const ValueKey('exit-fullscreen-stream-2')),
      findsNothing,
    );
  });

  testWidgets('phone watched stream can fill the occupant area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );
    s.voiceMap[20] = {
      1: VoiceUserState(),
      2: VoiceUserState(sharingScreen: true),
    };
    s.connectedVoiceChannelId = 20;
    s.voiceState = 'connected';

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(
      find.descendant(of: find.byType(VoiceStage), matching: find.text('Ada')),
      findsWidgets,
    );

    await tester.tap(find.text('Watch Stream'));
    await tester.pump();

    expect(find.text('0 FPS'), findsOneWidget);
    expect(find.byKey(const ValueKey('fullscreen-stream-2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fullscreen-stream-2')));
    await tester.pump();

    expect(
      find.descendant(of: find.byType(VoiceStage), matching: find.text('Ada')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('exit-fullscreen-stream-2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('exit-fullscreen-stream-2')));
    await tester.pump();

    expect(
      find.descendant(of: find.byType(VoiceStage), matching: find.text('Ada')),
      findsWidgets,
    );
  });

  testWidgets('phone voice stage uses large join and in-call controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'public!!',
      position: 1,
    );
    s.voiceMap[20] = {1: VoiceUserState()};

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Join Voice'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('join-voice'))).height,
      kVoiceJoinHeight,
    );

    final stageAvatars = tester.widgetList<UserAvatar>(
      find.descendant(
        of: find.byType(VoiceStage),
        matching: find.byType(UserAvatar),
      ),
    );
    expect(stageAvatars.any((a) => a.size == kVoiceTileAvatarPhone), isTrue);

    final menu = tester.widget<CompactIconButton>(
      find.descendant(
        of: find.byType(VoiceStage),
        matching: find.widgetWithIcon(CompactIconButton, Icons.menu),
      ),
    );
    expect(menu.size, minTap);

    s.connectedVoiceChannelId = 20;
    s.refresh();
    await tester.pump();

    const ctrl = Size(kVoiceCtrlBtn, kVoiceCtrlBtn);
    expect(tester.getSize(find.byKey(const ValueKey('voice-ctrl-mic'))), ctrl);
    expect(
      tester.getSize(find.byKey(const ValueKey('voice-ctrl-deafen'))),
      ctrl,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('voice-ctrl-output'))),
      ctrl,
    );
    expect(tester.getSize(find.byKey(const ValueKey('voice-ctrl-more'))), ctrl);
    expect(
      tester.getSize(find.byKey(const ValueKey('voice-ctrl-leave'))),
      ctrl,
    );
    expect(find.byKey(const ValueKey('voice-ctrl-cam')), findsNothing);
    expect(find.byKey(const ValueKey('voice-ctrl-share')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('voice-ctrl-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-ctrl-cam')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-ctrl-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-ctrl-keep-awake')), findsOneWidget);
    expect(find.text('Join Voice'), findsNothing);
  });

  testWidgets('open graph cards show title description and thumbnail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const thumb = 'https://cdn.example/og.png';
    await tester.pumpWidget(
      _app(
        _readySession(
          selectedChannelId: 10,
          messages: [
            KurierMessage(
              id: 1,
              channelId: 10,
              createdAt: 0,
              content: '<p>sharkord.brozantine.com/vanilla</p>',
              userId: 1,
              metadata: [
                {
                  'kind': 'open_graph',
                  'url': 'https://sharkord.brozantine.com/vanilla',
                  'title': 'Sharkord',
                  'siteName': 'Sharkord',
                  'description': 'Self-hosted messenger for small groups',
                  'images': [thumb],
                },
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Sharkord'), findsWidgets);
    expect(find.text('Self-hosted messenger for small groups'), findsOneWidget);
    expect(find.byKey(ogImageKey(thumb)), findsOneWidget);
  });

  testWidgets(
    'youtube urls render a Discord-style card with title and player',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const title = 'So I played Total War: Warhammer 40,000...';
      await tester.pumpWidget(
        _app(
          _readySession(
            selectedChannelId: 10,
            messages: [
              KurierMessage(
                id: 1,
                channelId: 10,
                createdAt: 0,
                content:
                    '<p>https://youtu.be/yxo4j0DdnwY?si=CkP3MrVqKwSYduW0</p>',
                userId: 1,
                metadata: [
                  {
                    'kind': 'open_graph',
                    'url': 'https://youtu.be/yxo4j0DdnwY?si=CkP3MrVqKwSYduW0',
                    'title': title,
                    'siteName': 'YouTube',
                    'author': 'BULKHEAD',
                    'description': 'A video on YouTube',
                    'images': [
                      'https://i.ytimg.com/vi/yxo4j0DdnwY/hqdefault.jpg',
                    ],
                  },
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(youtubeEmbedKey('yxo4j0DdnwY')), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('BULKHEAD'), findsOneWidget);
      expect(find.text('A video on YouTube'), findsNothing);
    },
  );

  testWidgets('gif urls embed without showing the link and can be favourited', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    const gifUrl = 'https://media.tenor.com/abc/tenor.gif';
    final s = _readySession(
      selectedChannelId: 10,
      messages: [
        KurierMessage(
          id: 1,
          channelId: 10,
          createdAt: 0,
          content: '<p>$gifUrl</p>',
          userId: 1,
        ),
      ],
    );
    await s.store.load();

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.pump();

    expect(find.text(gifUrl), findsNothing);
    expect(find.byKey(gifEmbedKey(gifUrl)), findsOneWidget);
    expect(find.byKey(gifFavouriteStarKey(gifUrl)), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsOneWidget);

    await tester.ensureVisible(find.byKey(gifFavouriteStarKey(gifUrl)));
    await tester.pump();
    await tester.tap(find.byKey(gifFavouriteStarKey(gifUrl)));
    await tester.pump();
    await tester.pump();

    expect(s.store.favoriteGifs(), [gifUrl]);
    expect(find.byIcon(Icons.star), findsOneWidget);

    await tester.tap(find.byIcon(Icons.gif_box_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Favourites'));
    await tester.pump();

    expect(find.text('No favourite GIFs yet'), findsNothing);
    expect(find.byIcon(Icons.star), findsWidgets);
  });

  testWidgets('uploaded image opens a zoomable lightbox', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        _readySession(
          selectedChannelId: 10,
          messages: [
            KurierMessage(
              id: 1,
              channelId: 10,
              createdAt: 0,
              content: '<p></p>',
              userId: 1,
              files: [
                _mediaFile(
                  id: 9,
                  name: 'photo.png',
                  originalName: 'photo.png',
                  mimeType: 'image/png',
                  extension: 'png',
                ),
              ],
            ),
            KurierMessage(
              id: 2,
              channelId: 10,
              createdAt: 1,
              content: '<p>later</p>',
              userId: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final thumb = find.byKey(imageAttachmentKey(9));
    expect(thumb, findsOneWidget);
    await tester.tap(thumb);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(kImageLightbox), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byKey(kFullscreenImage), findsOneWidget);
    expect(find.byKey(kCloseImageLightbox), findsOneWidget);

    await tester.tap(find.byKey(kFullscreenImage));
    await tester.pump();
    expect(find.byKey(kExitFullscreenImage), findsOneWidget);
    expect(find.byKey(kImageLightbox), findsOneWidget);

    await tester.tap(find.byKey(kExitFullscreenImage));
    await tester.pump();
    expect(find.byKey(kFullscreenImage), findsOneWidget);
    expect(find.byKey(kImageLightbox), findsOneWidget);

    await tester.tap(find.byKey(kCloseImageLightbox));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(kImageLightbox), findsNothing);
  });

  testWidgets('gif embed tap opens the image lightbox', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    const gifUrl = 'https://media.tenor.com/abc/tenor.gif';
    final s = _readySession(
      selectedChannelId: 10,
      messages: [
        KurierMessage(
          id: 1,
          channelId: 10,
          createdAt: 0,
          content: '<p>$gifUrl</p>',
          userId: 1,
        ),
      ],
    );
    await s.store.load();

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.pump();

    final gif = find.byKey(gifEmbedKey(gifUrl));
    expect(gif, findsOneWidget);
    final gifBox = tester.getRect(gif);
    await tester.tapAt(Offset(gifBox.left + 24, gifBox.top + 24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(kImageLightbox), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('image lightbox backdrop dismisses the popout', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        _readySession(
          selectedChannelId: 10,
          messages: [
            KurierMessage(
              id: 1,
              channelId: 10,
              createdAt: 0,
              content: '<p></p>',
              userId: 1,
              files: [
                _mediaFile(
                  id: 9,
                  name: 'photo.png',
                  originalName: 'photo.png',
                  mimeType: 'image/png',
                  extension: 'png',
                ),
              ],
            ),
            KurierMessage(
              id: 2,
              channelId: 10,
              createdAt: 1,
              content: '<p>later</p>',
              userId: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(imageAttachmentKey(9)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(kImageLightbox), findsOneWidget);

    await tester.tapAt(const Offset(12, 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(kImageLightbox), findsNothing);
  });

  testWidgets('uploaded mp4 embeds as a playable video', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        _readySession(
          selectedChannelId: 10,
          messages: [
            KurierMessage(
              id: 1,
              channelId: 10,
              createdAt: 0,
              content: '<p></p>',
              userId: 1,
              files: [_mediaFile()],
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(videoAttachmentKey('42')), findsOneWidget);
    expect(find.text('SNEEDING_HAS_STARTED_1.mp4'), findsNothing);
  });

  testWidgets('uploaded mp4 embeds on the phone overlay', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        _readySession(
          selectedChannelId: 10,
          messages: [
            KurierMessage(
              id: 1,
              channelId: 10,
              createdAt: 0,
              content:
                  '<p><a href="https://host/public/clip.mp4">SNEEDING_HAS_STARTED_1.mp4</a></p>',
              userId: 1,
              files: [_mediaFile()],
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(videoAttachmentKey('42')), findsOneWidget);
    expect(find.text('SNEEDING_HAS_STARTED_1.mp4'), findsNothing);
    final box = tester.getRect(find.byKey(videoAttachmentKey('42')));
    expect(box.width, lessThanOrEqualTo(kAttachmentMediaMaxWidth));
    expect(box.width, greaterThan(100));
  });

  testWidgets('uploaded mp3 embeds as a playable audio player', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        _readySession(
          selectedChannelId: 10,
          messages: [
            KurierMessage(
              id: 1,
              channelId: 10,
              createdAt: 0,
              content: '<p></p>',
              userId: 1,
              files: [
                _mediaFile(
                  id: 7,
                  name: 'track.mp3',
                  originalName: 'theme.mp3',
                  mimeType: 'audio/mpeg',
                  extension: 'mp3',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(audioAttachmentKey('7')), findsOneWidget);
    expect(find.text('theme.mp3'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('metadata video embeds when not already an attachment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const url = 'https://cdn.example/clip.webm';
    await tester.pumpWidget(
      _app(
        _readySession(
          selectedChannelId: 10,
          messages: [
            KurierMessage(
              id: 1,
              channelId: 10,
              createdAt: 0,
              content: '<p>$url</p>',
              userId: 1,
              metadata: [
                {'kind': 'media', 'url': url, 'mediaType': 'video/webm'},
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(videoAttachmentKey(url)), findsOneWidget);
    expect(find.text(url), findsNothing);
  });

  test('member list skips owner role and uses the next rank', () {
    final roles = {
      AppConfig.ownerRoleId: KurierRole(
        id: AppConfig.ownerRoleId,
        name: 'Owner',
        color: '#FFD700',
        position: 100,
        hoist: true,
        isDefault: false,
        isPersistent: true,
      ),
      10: KurierRole(
        id: 10,
        name: 'Super Trusted Freaks',
        color: '#EB459E',
        position: 50,
        hoist: true,
        isDefault: false,
        isPersistent: false,
      ),
    };
    final owner = KurierUser(
      id: 1,
      name: 'Ada',
      status: 'online',
      roleIds: [AppConfig.ownerRoleId, 10],
    );
    expect(isMemberListRole(roles[AppConfig.ownerRoleId]!), isFalse);
    expect(displayRole(owner, roles)?.id, 10);
    expect(displayRole(owner, roles, hoistedOnly: true)?.id, 10);
    expect(userRoleColor(owner, roles), const Color(0xFFEB459E));
  });

  test('member list uses the highest role even when it is not hoisted', () {
    final roles = {
      AppConfig.ownerRoleId: KurierRole(
        id: AppConfig.ownerRoleId,
        name: 'Owner',
        color: '#FFD700',
        position: 100,
        hoist: false,
        isDefault: false,
        isPersistent: true,
      ),
      10: KurierRole(
        id: 10,
        name: 'Super Trusted Freaks',
        color: '#EB459E',
        position: 50,
        hoist: false,
        isDefault: false,
        isPersistent: false,
      ),
      11: KurierRole(
        id: 11,
        name: 'Trusted Freaks',
        color: '#23A55A',
        position: 40,
        hoist: false,
        isDefault: false,
        isPersistent: false,
      ),
    };
    final owner = KurierUser(
      id: 1,
      name: 'Ada',
      status: 'online',
      roleIds: [AppConfig.ownerRoleId, 10, 11],
    );
    expect(displayRole(owner, roles)?.id, 10);
    expect(displayRole(owner, roles, hoistedOnly: true), isNull);
  });

  test('name color skips a white role and uses the next coloured role', () {
    final roles = {
      10: KurierRole(
        id: 10,
        name: 'Blank',
        color: '#ffffff',
        position: 50,
        hoist: true,
        isDefault: false,
        isPersistent: false,
      ),
      11: KurierRole(
        id: 11,
        name: 'Trusted Freaks',
        color: '#23A55A',
        position: 40,
        hoist: true,
        isDefault: false,
        isPersistent: false,
      ),
    };
    final user = KurierUser(id: 2, name: 'Gordon', roleIds: [10, 11]);
    expect(userRoleColor(user, roles), const Color(0xFF23A55A));
    expect(parseHexColor('#000000'), isNull);
  });

  test('name color uses the default Untrusted role when it is coloured', () {
    final roles = {
      AppConfig.ownerRoleId: KurierRole(
        id: AppConfig.ownerRoleId,
        name: 'Owner',
        color: '#FFD700',
        position: 100,
        hoist: true,
        isDefault: false,
        isPersistent: true,
      ),
      2: KurierRole(
        id: 2,
        name: 'Untrusted',
        color: '#ED4245',
        position: 0,
        hoist: false,
        isDefault: true,
        isPersistent: true,
      ),
    };
    final user = KurierUser(id: 3, name: 'KurierUser13138', roleIds: [2]);
    expect(isMemberListRole(roles[2]!), isFalse);
    expect(userRoleColor(user, roles), const Color(0xFFED4245));
    expect(
      userRoleColor(
        KurierUser(id: 1, name: 'HH', roleIds: [AppConfig.ownerRoleId, 2]),
        roles,
      ),
      const Color(0xFFED4245),
    );

    roles[2] = KurierRole(
      id: 2,
      name: 'Untrusted',
      color: '#ffffff',
      position: 0,
      hoist: false,
      isDefault: true,
      isPersistent: true,
    );
    expect(userRoleColor(user, roles), isNull);
  });

  testWidgets('message author uses role colour', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(
      selectedChannelId: 10,
      messages: [
        KurierMessage(
          id: 9,
          channelId: 10,
          createdAt: 0,
          content: '<p>hello overlay</p>',
          userId: 2,
        ),
      ],
    );
    s.roles[11] = KurierRole(
      id: 11,
      name: 'Trusted Freaks',
      color: '#23A55A',
      position: 40,
      hoist: true,
      isDefault: false,
      isPersistent: false,
    );
    s.users[2] = KurierUser(
      id: 2,
      name: 'Gordon',
      status: 'online',
      roleIds: [11],
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();

    final author = tester.widget<Text>(
      find.byKey(const ValueKey('msg-author-9')),
    );
    expect(author.data, 'Gordon');
    expect(author.style?.color, const Color(0xFF23A55A));
  });

  test('deleted users keep their original display name', () {
    expect(
      KurierUser(id: 4, name: 'huggy', deleted: true).displayName,
      'huggy',
    );
    expect(
      KurierUser(
        id: 4,
        name: 'huggy',
        nickname: 'Hug',
        deleted: true,
      ).displayName,
      'Hug',
    );
    expect(
      KurierUser(
        id: 4,
        name: AppConfig.deletedUserName,
        deleted: true,
      ).displayName,
      'Deleted',
    );

    final fromFlag = KurierUser.fromJson({
      'id': 4,
      'name': 'huggy',
      'deleted': true,
    });
    expect(fromFlag.deleted, isTrue);
    expect(fromFlag.displayName, 'huggy');

    final fromSentinel = KurierUser.fromJson({
      'id': 4,
      'name': AppConfig.deletedUserName,
    });
    expect(fromSentinel.deleted, isTrue);
    expect(fromSentinel.displayName, 'Deleted');
  });

  testWidgets('message author keeps tombstoned username', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(
      selectedChannelId: 10,
      messages: [
        KurierMessage(
          id: 9,
          channelId: 10,
          createdAt: 0,
          content: '<p>hello overlay</p>',
          userId: 2,
        ),
      ],
    );
    s.users[2] = KurierUser(
      id: 2,
      name: 'huggy',
      status: 'offline',
      deleted: true,
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();

    final author = tester.widget<Text>(
      find.byKey(const ValueKey('msg-author-9')),
    );
    expect(author.data, 'huggy');
    expect(find.text('Deleted'), findsNothing);
    expect(author.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('member list groups like Discord without an Owner header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.roles[AppConfig.ownerRoleId] = KurierRole(
      id: AppConfig.ownerRoleId,
      name: 'Owner',
      color: '#FFD700',
      position: 100,
      hoist: true,
      isDefault: false,
      isPersistent: true,
    );
    s.roles[10] = KurierRole(
      id: 10,
      name: 'Super Trusted Freaks',
      color: '#EB459E',
      position: 50,
      hoist: false,
      isDefault: false,
      isPersistent: false,
    );
    s.roles[11] = KurierRole(
      id: 11,
      name: 'Trusted Freaks',
      color: '#23A55A',
      position: 40,
      hoist: false,
      isDefault: false,
      isPersistent: false,
    );
    s.roles[2] = KurierRole(
      id: 2,
      name: 'Untrusted',
      color: '#ED4245',
      position: 0,
      hoist: false,
      isDefault: true,
      isPersistent: true,
    );
    s.users[1] = KurierUser(
      id: 1,
      name: 'Ada',
      status: 'online',
      roleIds: [AppConfig.ownerRoleId, 10],
    );
    s.users[2] = KurierUser(
      id: 2,
      name: 'Gordon',
      status: 'online',
      roleIds: [11],
    );
    s.users[3] = KurierUser(
      id: 3,
      name: 'OfflinePal',
      status: 'offline',
      roleIds: [11],
    );
    s.users[4] = KurierUser(
      id: 4,
      name: 'Newbie',
      status: 'online',
      roleIds: [2],
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('OWNER — 1'), findsNothing);
    expect(find.text('UNTRUSTED — 1'), findsNothing);
    expect(find.text('SUPER TRUSTED FREAKS — 1'), findsOneWidget);
    expect(find.text('TRUSTED FREAKS — 1'), findsOneWidget);
    expect(find.text('ONLINE — 1'), findsOneWidget);
    expect(find.text('OFFLINE — 1'), findsOneWidget);
    expect(find.text('Ada'), findsWidgets);
    expect(find.text('Gordon'), findsWidgets);
    expect(find.text('OfflinePal'), findsOneWidget);
    expect(find.text('Newbie'), findsOneWidget);

    final superTrusted = tester.getRect(find.text('SUPER TRUSTED FREAKS — 1'));
    final trusted = tester.getRect(find.text('TRUSTED FREAKS — 1'));
    final online = tester.getRect(find.text('ONLINE — 1'));
    final offline = tester.getRect(find.text('OFFLINE — 1'));
    expect(superTrusted.top, lessThan(trusted.top));
    expect(trusted.top, lessThan(online.top));
    expect(online.top, lessThan(offline.top));
  });

  testWidgets('member list moves a user offline when presence changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('ONLINE — 2'), findsOneWidget);
    expect(find.text('OFFLINE — 1'), findsNothing);
    expect(find.text('Gordon'), findsOneWidget);

    s.users[2]!.status = 'offline';
    s.refresh();
    await tester.pump();

    expect(find.text('ONLINE — 2'), findsNothing);
    expect(find.text('ONLINE — 1'), findsOneWidget);
    expect(find.text('OFFLINE — 1'), findsOneWidget);
    expect(find.text('Gordon'), findsOneWidget);
  });

  testWidgets('user settings overlay uses vanilla full-screen chrome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.overlay = 'userSettings';
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('USER SETTINGS'), findsWidgets);
    expect(find.text('Your Profile'), findsOneWidget);
    expect(
      find.text('Update your personal information and settings here.'),
      findsOneWidget,
    );
    expect(find.text('Profile'), findsWidgets);
  });

  testWidgets('desktop user settings tabs render native bodies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.overlay = 'userSettings';
    await tester.pumpWidget(_app(s));
    await tester.pump();

    await tester.tap(find.text('Devices').first);
    await tester.pumpAndSettle();
    expect(find.text('Voice Activity'), findsOneWidget);
    expect(find.text('Push to talk'), findsOneWidget);

    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Midnight'), findsOneWidget);

    final ocean = palettes[ThemePreset.ocean]!;
    final oceanStripe = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == ocean.background,
    );
    expect(oceanStripe, findsWidgets);
    final stripeSize = tester.getSize(oceanStripe.first);
    expect(stripeSize.height, greaterThan(24));
    expect(stripeSize.width, greaterThan(8));

    expect(
      find.byType(SettingsAccentSwatch),
      findsNWidgets(accentSwatches.length),
    );
    expect(tester.getSize(find.byType(SettingsAccentSwatch).first).height, 28);

    await tester.tap(find.text('Sounds').first);
    await tester.pumpAndSettle();
    expect(find.text('Open sound library'), findsOneWidget);

    await tester.tap(find.text('Open sound library'));
    await tester.pumpAndSettle();
    expect(find.text('Sound library'), findsOneWidget);
    expect(find.text('Mention sound'), findsOneWidget);
    expect(find.text('Message sound'), findsOneWidget);
    expect(find.text('Play'), findsNWidgets(KurierSoundType.all.length));
    expect(find.text('Message received'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notifications').first);
    await tester.pumpAndSettle();
    expect(find.text('Replies to me'), findsOneWidget);

    await tester.tap(find.text('Password').first);
    await tester.pumpAndSettle();
    expect(find.text('Confirm new password'), findsOneWidget);

    await tester.tap(find.text('Security').first);
    await tester.pumpAndSettle();
    expect(find.text('Current password'), findsOneWidget);

    await tester.tap(find.text('Others').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Automatically rejoin the last channel on connect.'),
      findsOneWidget,
    );
  });

  testWidgets('phone user settings is a list that drills into profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.overlay = 'userSettings';
    await tester.pumpWidget(_app(s));
    await tester.pumpAndSettle();

    expect(find.text('User settings'), findsOneWidget);
    expect(find.text('USER SETTINGS'), findsNothing);
    expect(find.text('Ada'), findsWidgets);
    expect(find.text('@Ada'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(
      find.text('Update your personal information and settings here.'),
      findsNothing,
    );

    await tester.tap(find.text('@Ada'));
    await tester.pumpAndSettle();

    expect(
      find.text('Update your personal information and settings here.'),
      findsOneWidget,
    );
    expect(find.text('Optional display nickname'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('Devices'), findsNothing);
    expect(find.text('Disconnect'), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('User settings'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(
      find.text('Update your personal information and settings here.'),
      findsNothing,
    );
  });

  testWidgets('server menu hides user settings and unpermitted actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    await tester.pumpWidget(_app(s));
    await tester.pump();

    await tester.tap(find.text('Test Server'));
    await tester.pumpAndSettle();

    expect(find.text('User settings'), findsNothing);
    expect(find.text('Server settings'), findsNothing);
    expect(find.text('Create channel'), findsNothing);
    expect(find.text('Create category'), findsNothing);
    expect(find.text('Disconnect'), findsOneWidget);

    await tester.tapAt(const Offset(800, 400));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    expect(s.overlay, 'userSettings');
  });

  testWidgets('server menu shows only permitted actions plus disconnect', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.roles[AppConfig.ownerRoleId] = KurierRole(
      id: AppConfig.ownerRoleId,
      name: 'Owner',
      color: '#FFD700',
      position: 100,
      hoist: true,
      isDefault: false,
      isPersistent: true,
      permissions: Permission.all,
    );
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    await tester.pumpWidget(_app(s));
    await tester.pump();

    await tester.tap(find.text('Test Server'));
    await tester.pumpAndSettle();

    expect(find.text('User settings'), findsNothing);
    expect(find.text('Server settings'), findsOneWidget);
    expect(find.text('Create channel'), findsOneWidget);
    expect(find.text('Create category'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
  });

  testWidgets('welcome overlay is a centered dialog', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.overlay = 'welcome';
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Welcome to Test Server'), findsOneWidget);
    expect(
      find.text("Let's set up your profile to get started."),
      findsOneWidget,
    );
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Save and continue'), findsOneWidget);
    expect(find.text('USER SETTINGS'), findsNothing);
  });

  testWidgets('phone server settings is a list that drills into a tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession();
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings');
    await tester.pumpWidget(_app(s));
    await tester.pumpAndSettle();

    expect(find.text('Server settings'), findsOneWidget);
    expect(find.text('SERVER SETTINGS'), findsNothing);
    expect(find.text('Test Server'), findsWidgets);
    expect(find.text('General'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(
      find.text('Manage server users and their permissions'),
      findsNothing,
    );

    await tester.ensureVisible(find.text('Users'));
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();

    expect(
      find.text('Manage server users and their permissions'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('General'), findsNothing);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Server settings'), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Server settings'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(
      find.text('Manage server users and their permissions'),
      findsNothing,
    );
  });

  testWidgets('tablet server settings uses the compact overlay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession();
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings');
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Server settings'), findsOneWidget);
    expect(find.text('SERVER SETTINGS'), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
    expect(
      find.text('Manage server users and their permissions'),
      findsNothing,
    );
  });

  testWidgets('desktop server settings keeps two-column chrome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'users');
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('SERVER SETTINGS'), findsOneWidget);
    expect(find.text('Users'), findsWidgets);
    expect(
      find.text('Manage server users and their permissions'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('desktop audit log matches vanilla layout', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'audit');
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.pump();

    expect(find.text('Audit Log'), findsWidgets);
    expect(find.text('Recent server actions, newest first.'), findsOneWidget);
    expect(find.text('All actions'), findsOneWidget);
    expect(find.text('All users'), findsOneWidget);
    expect(find.text('No audit log entries yet.'), findsOneWidget);
  });

  testWidgets('desktop access bans shows IP, hardware, and browser cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'accessBans');
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.pump();

    expect(find.text('IP bans'), findsOneWidget);
    expect(find.text('Hardware bans'), findsOneWidget);
    expect(find.text('Browser bans'), findsOneWidget);
    expect(find.text('This browser'), findsOneWidget);
    expect(find.text('Address'), findsWidgets);
    expect(find.text('Reason (optional)'), findsWidgets);
    expect(find.text('Add ban'), findsWidgets);
    expect(find.text('No hardware addresses are banned.'), findsOneWidget);
    expect(find.text('No browsers are banned.'), findsOneWidget);
  });

  testWidgets('desktop security log shows locked accounts and filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'security');
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.pump();

    expect(find.text('Locked accounts'), findsOneWidget);
    expect(find.text('No accounts are locked.'), findsOneWidget);
    expect(find.text('Security'), findsWidgets);
    expect(
      find.text(
        'Failed logins and security-question attempts. Only the owner can see this log.',
      ),
      findsOneWidget,
    );
    expect(find.text('All actions'), findsOneWidget);
    expect(find.text('All users'), findsOneWidget);
  });

  testWidgets('desktop roles split pane shows empty editor hint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.roles[10] = KurierRole(
      id: 10,
      name: 'Trusted',
      color: '#57F287',
      position: 1,
      hoist: false,
      isDefault: true,
      isPersistent: false,
    );
    s.openOverlay('serverSettings', tab: 'roles');
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Trusted'), findsOneWidget);
    expect(
      find.text('Select a role to edit or create a new one.'),
      findsOneWidget,
    );
  });

  testWidgets('desktop emojis show upload empty state', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'emojis');
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Search emojis...'), findsOneWidget);
    expect(find.text('Upload Custom Emojis'), findsOneWidget);
    expect(find.text('Upload Emoji'), findsOneWidget);
  });

  testWidgets('desktop users tab has search and member rows', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'users');
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Search users by name or identity...'), findsOneWidget);
    expect(find.text('Ada'), findsWidgets);
    expect(find.text('Gordon'), findsWidgets);
    expect(find.text('Online'), findsWidgets);
  });

  testWidgets('desktop users tab fills the settings content area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'users');
    await tester.pumpWidget(_app(s));
    await tester.pump();

    const chromePad = 80.0;
    final panel = tester.getSize(find.byType(SettingsPanel));
    expect(panel.width, closeTo(1920 - kSettingsNavWidth - chromePad, 0.5));
    expect(panel.width, greaterThan(kSettingsContentMax));
  });

  testWidgets('desktop reset passwords requires confirm field', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'resetPasswords');
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Select a user'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm New Password'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('desktop invites shows empty state', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'invites');
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.pump();

    expect(find.text('Create invite'), findsOneWidget);
    expect(find.text('Search invites by code or creator...'), findsOneWidget);
    expect(find.text('No invites found'), findsOneWidget);
  });

  testWidgets('desktop plugins has installed and marketplace tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'plugins');
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.pump();

    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Marketplace'), findsOneWidget);
    expect(find.text('Manage installed plugins'), findsOneWidget);
  });

  testWidgets('desktop storage matches vanilla controls and save flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.openOverlay('serverSettings', tab: 'storage');
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.pump();

    expect(find.text('Storage'), findsWidgets);
    expect(find.text('Allow uploads'), findsOneWidget);
    expect(
      find.text(
        'Allows users to upload files to the server. Existing files won\'t be affected.',
      ),
      findsOneWidget,
    );
    expect(find.text('Allow file sharing in direct messages'), findsOneWidget);
    expect(find.text('Quota'), findsOneWidget);
    expect(find.text('Max file size'), findsOneWidget);
    expect(find.text('Max avatar size'), findsOneWidget);
    expect(find.text('Max banner size'), findsOneWidget);
    expect(find.text('Quota per user'), findsOneWidget);
    expect(find.text('Max files per message'), findsOneWidget);
    expect(find.text('Overflow action'), findsOneWidget);
    expect(find.text('Enable image optimization'), findsOneWidget);
    expect(find.text('Signed URLs'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Unlimited'), findsWidgets);
    expect(find.text('2.00 GB'), findsOneWidget);
  });

  testWidgets('member menu hides moderation without permissions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    await tester.pumpWidget(_app(s));
    await tester.pump();

    await tester.longPress(find.text('Gordon'));
    await tester.pumpAndSettle();

    expect(find.text('View profile'), findsOneWidget);
    expect(find.text('Message'), findsWidgets);
    expect(find.text('Mute locally'), findsOneWidget);
    expect(find.text('Copy username'), findsOneWidget);
    expect(find.text('Copy user ID'), findsOneWidget);
    expect(find.text('Kick from server'), findsNothing);
    expect(find.text('Ban from server'), findsNothing);
    expect(find.text('Manage roles'), findsNothing);
    expect(find.text('Set nickname'), findsNothing);
    expect(find.text('Server mute'), findsNothing);
    expect(find.text('Server Activity'), findsNothing);
    expect(find.text('IP Address'), findsNothing);
  });

  testWidgets('member menu shows permitted moderation for the owner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.roles[AppConfig.ownerRoleId] = KurierRole(
      id: AppConfig.ownerRoleId,
      name: 'Owner',
      color: '#FFD700',
      position: 100,
      hoist: true,
      isDefault: false,
      isPersistent: true,
      permissions: Permission.all,
    );
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'Lounge',
      position: 1,
    );
    await tester.pumpWidget(_app(s));
    await tester.pump();

    await tester.longPress(find.text('Gordon'));
    await tester.pumpAndSettle();

    expect(find.text('View profile'), findsOneWidget);
    expect(find.text('Set nickname'), findsOneWidget);
    expect(find.text('Move to voice channel'), findsOneWidget);
    expect(find.text('Manage roles'), findsOneWidget);
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('Server mute'), findsOneWidget);
    expect(find.text('Kick from server'), findsOneWidget);
    expect(find.text('Ban from server'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('owner member menu shows hidden browser token and ban', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const token = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    final s = _readySession(selectedChannelId: 10);
    _grantOwner(s);
    s.userInfoOverride = (id) => id == 2
        ? UserAdminInfo(
            user: s.users[2]!,
            logins: const [
              UserLoginInfo(
                ip: '203.0.113.9',
                country: 'US',
                city: 'Austin',
                deviceToken: token,
              ),
            ],
          )
        : null;

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.longPress(find.text('Gordon'));
    await tester.pumpAndSettle();

    expect(find.text('Browser token'), findsOneWidget);
    expect(find.text('Ban browser'), findsOneWidget);
    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    expect(find.text(token), findsNothing);

    final row = find
        .ancestor(
          of: find.byIcon(Icons.fingerprint),
          matching: find.byType(Row),
        )
        .first;
    await tester.tap(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.visibility_outlined),
      ),
    );
    await tester.pump();
    expect(find.text(token), findsOneWidget);

    await tester.tap(find.text('Ban browser'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Permanently block this browser from logging in or creating accounts. Owner accounts are not blocked.',
      ),
      findsOneWidget,
    );
    expect(find.text('Browser token'), findsOneWidget);
  });

  testWidgets('member menu hides browser token for non-owners', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.roles[10] = KurierRole(
      id: 10,
      name: 'Mod',
      color: '#EB459E',
      position: 50,
      hoist: true,
      isDefault: false,
      isPersistent: false,
      permissions: const [
        Permission.manageUsers,
        Permission.viewUserSensitiveData,
      ],
    );
    s.users[1] = s.users[1]!.copyWith(roleIds: [10]);
    s.userInfoOverride = (_) => UserAdminInfo(
      user: s.users[2]!,
      logins: const [
        UserLoginInfo(
          ip: '203.0.113.9',
          country: 'US',
          city: 'Austin',
          deviceToken: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        ),
      ],
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.longPress(find.text('Gordon'));
    await tester.pumpAndSettle();

    expect(find.text('IP Address'), findsOneWidget);
    expect(find.text('Browser token'), findsNothing);
    expect(find.text('Ban browser'), findsNothing);
    expect(find.byIcon(Icons.fingerprint), findsNothing);
  });

  testWidgets('admin without owner role cannot see browser token row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.roles[10] = KurierRole(
      id: 10,
      name: 'Admin',
      color: '#EB459E',
      position: 50,
      hoist: true,
      isDefault: false,
      isPersistent: false,
      permissions: Permission.all,
    );
    s.users[1] = s.users[1]!.copyWith(roleIds: [10]);
    s.userInfoOverride = (_) => UserAdminInfo(
      user: s.users[2]!,
      logins: const [
        UserLoginInfo(
          ip: '203.0.113.9',
          country: 'US',
          city: 'Austin',
          deviceToken: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        ),
      ],
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.longPress(find.text('Gordon'));
    await tester.pumpAndSettle();

    expect(find.text('IP Address'), findsOneWidget);
    expect(find.text('Browser token'), findsNothing);
    expect(find.text('Ban browser'), findsNothing);
    expect(find.byIcon(Icons.fingerprint), findsNothing);
  });

  testWidgets('phone profile sheet shows voice, volume, and overflow mods', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession();
    s.roles[AppConfig.ownerRoleId] = KurierRole(
      id: AppConfig.ownerRoleId,
      name: 'Owner',
      color: '#FFD700',
      position: 100,
      hoist: true,
      isDefault: false,
      isPersistent: true,
      permissions: Permission.all,
    );
    s.roles[10] = KurierRole(
      id: 10,
      name: 'LONESTAR',
      color: '#EB459E',
      position: 50,
      hoist: true,
      isDefault: false,
      isPersistent: false,
    );
    s.users[1] = s.users[1]!.copyWith(roleIds: [AppConfig.ownerRoleId]);
    s.users[2] = KurierUser(
      id: 2,
      name: 'Gordon',
      status: 'online',
      pronouns: 'they/them',
      statusMessage: 'INTJ Gaymer',
      bio: 'Certified INTJ Gamerboi',
      createdAt: DateTime(2026, 8, 23).millisecondsSinceEpoch,
      roleIds: [10],
    );
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'Voice 1',
      position: 1,
    );
    s.voiceMap[20] = {2: VoiceUserState()};

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.tap(find.text('Gordon'));
    await tester.pumpAndSettle();

    expect(find.text('Message'), findsOneWidget);
    expect(find.text('@Gordon'), findsOneWidget);
    expect(find.text('they/them'), findsOneWidget);
    expect(find.text('INTJ Gaymer'), findsOneWidget);
    expect(find.text('Certified INTJ Gamerboi'), findsOneWidget);
    expect(find.text('Aug 23, 2026'), findsOneWidget);
    expect(find.text('LONESTAR', skipOffstage: false), findsOneWidget);
    expect(find.text('In voice'), findsOneWidget);
    expect(find.text('Join Voice'), findsOneWidget);
    expect(find.text('User volume'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Add Friend'), findsNothing);
    expect(find.text('Call'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('profile-overflow')));
    await tester.pumpAndSettle();

    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Copy username'), findsOneWidget);
    expect(find.text('Copy user ID'), findsOneWidget);
    expect(find.text('Mute locally'), findsOneWidget);
    expect(find.text('Kick from server', skipOffstage: false), findsOneWidget);
    expect(find.text('Ban from server', skipOffstage: false), findsOneWidget);
    expect(find.text('Server mute', skipOffstage: false), findsOneWidget);
    expect(find.text('Add Friend'), findsNothing);
    expect(find.text('Remove Friend'), findsNothing);
    expect(find.text('Block'), findsNothing);
    expect(find.text('Invite to Server'), findsNothing);
    expect(find.text('Apps'), findsNothing);
    expect(find.text('Ignore'), findsNothing);
    expect(find.text('Report User Profile'), findsNothing);
    expect(find.text('View Main Profile'), findsNothing);
  });

  testWidgets('phone overflow hides moderation without permissions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession();
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'Voice 1',
      position: 1,
    );
    s.voiceMap[20] = {2: VoiceUserState()};

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.tap(find.text('Gordon'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-overflow')));
    await tester.pumpAndSettle();

    expect(find.text('Copy username'), findsNothing);
    expect(find.text('Copy user ID'), findsNothing);
    expect(find.text('Mute locally'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Kick from server'), findsNothing);
    expect(find.text('Ban from server'), findsNothing);
    expect(find.text('Server mute'), findsNothing);
    expect(find.text('Manage roles'), findsNothing);
  });

  test('formatMemberSince uses a short month name', () {
    expect(
      formatMemberSince(DateTime(2026, 8, 23).millisecondsSinceEpoch),
      'Aug 23, 2026',
    );
    expect(formatMemberSince(0), '');
  });

  test('profileHandle prefixes the username', () {
    expect(profileHandle(KurierUser(id: 1, name: 'rf4burns')), '@rf4burns');
  });

  test('desktopPopoutOffset prefers the right of the click and clamps', () {
    const view = Size(1280, 800);
    const pad = EdgeInsets.zero;
    final beside = desktopPopoutOffset(
      view: view,
      pad: pad,
      anchor: const Offset(200, 120),
      width: 300,
    );
    expect(beside.dx, 212);
    expect(beside.dy, 120);

    final flipped = desktopPopoutOffset(
      view: view,
      pad: pad,
      anchor: const Offset(1200, 40),
      width: 300,
    );
    expect(flipped.dx, lessThan(1200 - 300));
    expect(flipped.dx, greaterThanOrEqualTo(8));
    expect(flipped.dy, 40);
  });

  testWidgets('desktop profile popout matches native style', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.roles[10] = KurierRole(
      id: 10,
      name: 'LONESTAR',
      color: '#EB459E',
      position: 50,
      hoist: true,
      isDefault: false,
      isPersistent: false,
    );
    s.users[2] = KurierUser(
      id: 2,
      name: 'Gordon',
      status: 'online',
      pronouns: 'they/them',
      statusMessage: 'INTJ Gaymer',
      bio: 'Certified INTJ Gamerboi',
      createdAt: DateTime(2026, 8, 23).millisecondsSinceEpoch,
      roleIds: [10],
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.tap(find.text('Gordon'));
    await tester.pumpAndSettle();

    expect(s.profileUser?.id, 2);
    expect(s.profileAnchor, isNotNull);
    expect(find.byKey(const ValueKey('profile-popout')), findsOneWidget);
    expect(find.byType(ProfileAvatarBadge), findsOneWidget);
    expect(find.text('@Gordon'), findsOneWidget);
    expect(find.text('they/them'), findsOneWidget);
    expect(find.text('ROLES'), findsOneWidget);
    expect(find.text('LONESTAR'), findsOneWidget);
    expect(find.byType(RoleChip), findsWidgets);
    expect(find.text('Member Since'), findsOneWidget);
    expect(find.text('Aug 23, 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-message')), findsOneWidget);
    expect(find.text('Add Friend'), findsNothing);

    s.closeOverlay();
    await tester.pump();
    expect(s.profileUser, isNull);
    expect(s.profileAnchor, isNull);
    expect(find.byKey(const ValueKey('profile-popout')), findsNothing);
  });

  testWidgets('tapping a user mention opens the profile popout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(
      selectedChannelId: 10,
      messages: [
        KurierMessage(
          id: 50,
          channelId: 10,
          createdAt: 0,
          content:
              '<p><span data-type="mention" data-mention-kind="user" data-user-id="2">@Gordon</span></p>',
          userId: 1,
        ),
      ],
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.tap(find.textContaining('@Gordon'));
    await tester.pumpAndSettle();

    expect(s.profileUser?.id, 2);
    expect(s.profileAnchor, isNotNull);
    expect(find.byKey(const ValueKey('profile-popout')), findsOneWidget);
  });

  test('canModerate requires a higher role and never targets yourself', () {
    final s = _readySession();
    s.roles[10] = KurierRole(
      id: 10,
      name: 'Mod',
      color: '#23A55A',
      position: 40,
      hoist: true,
      isDefault: false,
      isPersistent: false,
    );
    s.roles[2] = KurierRole(
      id: 2,
      name: 'Untrusted',
      color: '#ED4245',
      position: 0,
      hoist: false,
      isDefault: true,
      isPersistent: true,
    );
    s.users[1] = s.users[1]!.copyWith(roleIds: [10]);
    s.users[2] = s.users[2]!.copyWith(roleIds: [2]);
    expect(s.canModerate(s.users[1]!), isFalse);
    expect(s.canModerate(s.users[2]!), isTrue);
  });

  testWidgets('voice connected shows ping and opens transport stats on tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 20);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'General',
      position: 1,
    );
    s.connectedVoiceChannelId = 20;
    s.voiceState = 'connected';
    s.voiceRttMs = 23;
    s.transportStats = TransportStatsData(
      producer: const TransportRtpStats(
        packetsSent: 12,
        rtt: 23.4,
        bytesSent: 4000,
      ),
      consumer: const TransportRtpStats(
        packetsReceived: 40,
        packetsLost: 2,
        bytesReceived: 8000,
      ),
      currentBitrateSent: 1200,
      currentBitrateReceived: 3400,
      totalBytesSent: 9000,
      totalBytesReceived: 16000,
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('Voice connected'), findsOneWidget);
    expect(find.text('23 ms'), findsOneWidget);
    expect(find.text('Transport Statistics'), findsNothing);
    expect(find.text('Disconnect'), findsOneWidget);

    await tester.tap(find.text('Voice connected'));
    await tester.pumpAndSettle();

    expect(find.text('Transport Statistics'), findsOneWidget);
    expect(find.text('Outgoing'), findsOneWidget);
    expect(find.text('Incoming'), findsOneWidget);
    expect(find.textContaining('RTT:'), findsOneWidget);

    await tester.tapAt(const Offset(900, 80));
    await tester.pumpAndSettle();
    expect(find.text('Transport Statistics'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(AccountBar),
        matching: find.byIcon(Icons.mic),
      ),
    );
    await tester.pump();
    expect(s.micMuted, isTrue);

    await tester.tap(find.text('Disconnect'));
    await tester.pump();
    expect(s.connectedVoiceChannelId, isNull);
    expect(s.voiceState, 'idle');
  });

  testWidgets('compact voice bar returns to the voice channel', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'General',
      position: 1,
    );
    s.connectedVoiceChannelId = 20;
    s.voiceState = 'connected';

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.byType(CompactVoiceBar), findsOneWidget);
    expect(find.byType(VoiceStage), findsNothing);
    expect(find.byKey(const ValueKey('compact-voice-output')), findsOneWidget);
    expect(find.byKey(const ValueKey('compact-voice-stats')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('return-to-voice')));
    await tester.pumpAndSettle();

    expect(s.selectedChannelId, 20);
    expect(s.connectedVoiceChannelId, 20);
    expect(s.voiceState, 'connected');
    expect(find.byType(VoiceStage), findsOneWidget);
    expect(find.byType(CompactVoiceBar), findsNothing);
  });

  testWidgets('compact voice bar stats icon opens transport stats', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'General',
      position: 1,
    );
    s.connectedVoiceChannelId = 20;
    s.voiceState = 'connected';
    s.voiceRttMs = 23;
    s.transportStats = TransportStatsData(
      producer: const TransportRtpStats(
        packetsSent: 12,
        rtt: 23.4,
        bytesSent: 4000,
      ),
      consumer: const TransportRtpStats(
        packetsReceived: 40,
        packetsLost: 2,
        bytesReceived: 8000,
      ),
      currentBitrateSent: 1200,
      currentBitrateReceived: 3400,
      totalBytesSent: 9000,
      totalBytesReceived: 16000,
    );

    await tester.pumpWidget(_app(s));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('compact-voice-stats')));
    await tester.pumpAndSettle();

    expect(find.text('Transport Statistics'), findsOneWidget);
    expect(s.selectedChannelId, 10);
    expect(s.connectedVoiceChannelId, 20);
    expect(s.voiceState, 'connected');
  });

  testWidgets('sidebar voice bar returns to the voice channel from chat', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.channels[20] = KurierChannel(
      id: 20,
      type: 'VOICE',
      name: 'General',
      position: 1,
    );
    s.connectedVoiceChannelId = 20;
    s.voiceState = 'connected';

    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.byType(VoiceControlBar), findsOneWidget);
    expect(find.byType(VoiceStage), findsNothing);

    await tester.tap(find.byKey(const ValueKey('voice-control-status')));
    await tester.pumpAndSettle();

    expect(s.selectedChannelId, 20);
    expect(s.connectedVoiceChannelId, 20);
    expect(s.voiceState, 'connected');
    expect(find.byType(VoiceStage), findsOneWidget);
    expect(find.byType(CompactVoiceBar), findsNothing);
    expect(find.text('Transport Statistics'), findsNothing);
  });

  testWidgets('message context menu shows only permitted actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();
    await tester.longPress(find.text('hello overlay'));
    await tester.pumpAndSettle();

    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete message'), findsOneWidget);
    expect(find.text('Reply'), findsNothing);
    expect(find.text('Add reaction'), findsNothing);
    expect(find.text('Pin message'), findsNothing);
  });

  testWidgets('owner message context menu groups reactions and actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    _grantOwner(s);
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.longPress(find.text('hello overlay'));
    await tester.pumpAndSettle();

    expect(find.text('Add reaction'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Reply in thread'), findsOneWidget);
    expect(find.text('Pin message'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Delete message'), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-react-+1')), findsOneWidget);
  });

  testWidgets('phone message context menu matches desktop grouping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    _grantOwner(s);
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.longPress(find.text('hello overlay'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-react-+1')), findsOneWidget);
    expect(find.text('Add reaction'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Reply in thread'), findsOneWidget);
    expect(find.text('Pin message'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Delete message'), findsOneWidget);
    expect(find.text('Close'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('Add reaction'),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .height,
      lessThan(40),
    );
  });

  testWidgets('tablet message context menu matches desktop grouping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    _grantOwner(s);
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.longPress(find.text('hello overlay'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-react-+1')), findsOneWidget);
    expect(find.text('Add reaction'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Reply in thread'), findsOneWidget);
    expect(find.text('Pin message'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Delete message'), findsOneWidget);
    expect(find.text('Close'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('Add reaction'),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .height,
      lessThan(40),
    );
  });

  testWidgets('desktop message hover bar shows actions then more menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    _grantOwner(s);
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.byKey(const ValueKey('hover-more')), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('hello overlay')));
    await tester.pump();

    expect(find.byKey(const ValueKey('hover-add-reaction')), findsOneWidget);
    expect(find.byKey(const ValueKey('hover-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('hover-pin')), findsOneWidget);
    expect(find.byKey(const ValueKey('hover-reply')), findsOneWidget);
    expect(find.byKey(const ValueKey('hover-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('hover-more')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hover-more')));
    await tester.pumpAndSettle();

    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Reply in thread'), findsOneWidget);
    expect(find.text('Delete message'), findsOneWidget);
  });

  testWidgets('message hover bar hides unpermitted actions', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('hello overlay')));
    await tester.pump();

    expect(find.byKey(const ValueKey('hover-add-reaction')), findsNothing);
    expect(find.byKey(const ValueKey('hover-pin')), findsNothing);
    expect(find.byKey(const ValueKey('hover-reply')), findsNothing);
    expect(find.byKey(const ValueKey('hover-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('hover-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('hover-more')), findsOneWidget);
  });

  testWidgets('message hover bar omits unavailable actions on others', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(
      selectedChannelId: 10,
      messages: [
        KurierMessage(
          id: 1,
          channelId: 10,
          createdAt: 0,
          content: '<p>hello overlay</p>',
          userId: 2,
        ),
      ],
    );
    await tester.pumpWidget(_app(s));
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('hello overlay')));
    await tester.pump();

    expect(find.byKey(const ValueKey('hover-add-reaction')), findsNothing);
    expect(find.byKey(const ValueKey('hover-edit')), findsNothing);
    expect(find.byKey(const ValueKey('hover-pin')), findsNothing);
    expect(find.byKey(const ValueKey('hover-reply')), findsNothing);
    expect(find.byKey(const ValueKey('hover-more')), findsNothing);
    expect(find.byKey(const ValueKey('hover-copy')), findsOneWidget);
  });

  testWidgets('channel context menu hides unpermitted manage actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_readySession(selectedChannelId: 10)));
    await tester.pump();
    await tester.longPress(find.text('general').first);
    await tester.pumpAndSettle();

    expect(find.text('All messages'), findsOneWidget);
    expect(find.text('Mentions only'), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Channel settings'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  Finder _notifyRowCheck(String label) {
    return find.descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      ),
      matching: find.byKey(const ValueKey('menu-selected')),
    );
  }

  testWidgets('channel context menu ticks the current notification level', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.notificationOverrides[10] = 'nothing';
    await tester.pumpWidget(_app(s));
    await tester.pump();
    await tester.longPress(find.text('general').first);
    await tester.pumpAndSettle();

    expect(_notifyRowCheck('Mute'), findsOneWidget);
    expect(_notifyRowCheck('All messages'), findsNothing);
    expect(_notifyRowCheck('Mentions only'), findsNothing);
  });

  test('web client defaults automatic gain control off', () {
    expect(HostsStore().autoGainControl, isFalse);
    expect(HostsStore().echoCancellation, isTrue);
    expect(HostsStore().keepScreenOnVoice, isFalse);
  });

  testWidgets('UserAvatar shows a phone pip only when mobile-online', (
    tester,
  ) async {
    final session = SessionController();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(ThemePreset.dark, overlayAccent),
        home: Column(
          children: [
            UserAvatar(
              user: KurierUser(
                id: 1,
                name: 'Ada',
                status: 'online',
                mobile: true,
              ),
              session: session,
            ),
            UserAvatar(
              user: KurierUser(id: 2, name: 'Gordon', status: 'online'),
              session: session,
            ),
            UserAvatar(
              user: KurierUser(
                id: 3,
                name: 'Offline',
                status: 'offline',
                mobile: true,
              ),
              session: session,
            ),
            UserAvatar(
              user: KurierUser(
                id: 4,
                name: 'AwayPhone',
                status: 'idle',
                mobile: true,
              ),
              session: session,
            ),
          ],
        ),
      ),
    );

    expect(find.byKey(const ValueKey('mobile-status')), findsNWidgets(2));
  });

  testWidgets('desktop rail toggles Online and Away', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.byKey(const ValueKey('presence-toggle')), findsOneWidget);
    expect(find.text('Online'), findsWidgets);
    expect(s.displayPresence, 'online');

    await tester.tap(find.byKey(const ValueKey('presence-toggle')));
    await tester.pump();

    expect(s.displayPresence, 'idle');
    expect(s.me?.status, 'idle');
    expect(find.text('Away'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('presence-toggle')));
    await tester.pump();
    expect(s.displayPresence, 'online');
  });

  testWidgets('phone hides the rail presence button and avatar tap toggles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession();
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.byKey(const ValueKey('presence-toggle')), findsNothing);
    expect(s.displayPresence, 'online');

    await tester.tap(
      find.descendant(
        of: find.byType(AccountBar),
        matching: find.byType(UserAvatar),
      ),
    );
    await tester.pump();

    expect(s.displayPresence, 'idle');
    expect(s.overlay, isNot('userSettings'));
    expect(find.text('Away'), findsWidgets);
  });

  testWidgets('idle members stay in the online list and profile says Away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _readySession(selectedChannelId: 10);
    s.users[2]!.status = 'idle';
    await tester.pumpWidget(_app(s));
    await tester.pump();

    expect(find.text('ONLINE — 2'), findsOneWidget);
    expect(find.text('OFFLINE — 1'), findsNothing);

    await tester.tap(find.text('Gordon'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-popout')), findsOneWidget);
    expect(find.text('Away'), findsOneWidget);
  });
}

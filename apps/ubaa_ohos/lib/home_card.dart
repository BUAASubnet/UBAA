import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:ubaa_host/ubaa_host.dart';

final class OhosHomeCard {
  const OhosHomeCard();

  static const _channel = MethodChannel('cn.edu.buaa.ubaa/home-card');

  Future<void> publish(HomeCardSnapshot snapshot) =>
      _channel.invokeMethod<void>('publish', {
        'payload': jsonEncode({
          'version': 2,
          'campusDay': snapshot.campusDay,
          'dateLabel': snapshot.dateLabel,
          'signedIn': snapshot.signedIn,
          'agenda': [for (final item in snapshot.agenda) _item(item)],
          'homework': [for (final item in snapshot.homework) _item(item)],
          'todo': [for (final item in snapshot.todo) _item(item)],
        }),
      });

  static Map<String, Object> _item(HomeCardItem item) => {
    'title': item.title,
    'time': item.time,
    'location': ?item.location,
  };
}

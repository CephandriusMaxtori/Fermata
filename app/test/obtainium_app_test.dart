import 'dart:convert';

import 'package:fermata/src/update/obtainium_app.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = ObtainiumApp(
  id: 'com.hoid.fermata',
  url: 'https://github.com/CephandriusMaxtori/Fermata',
  author: 'CephandriusMaxtori',
  name: 'Fermata',
);

void main() {
  group('ObtainiumApp.fromJson', () {
    test('reads every field Obtainium requires', () {
      final app = ObtainiumApp.fromJson({
        'id': 'com.hoid.fermata',
        'url': 'https://github.com/CephandriusMaxtori/Fermata',
        'author': 'CephandriusMaxtori',
        'name': 'Fermata',
      });

      expect(app.id, 'com.hoid.fermata');
      expect(app.name, 'Fermata');
      expect(app.author, 'CephandriusMaxtori');
      expect(app.url, 'https://github.com/CephandriusMaxtori/Fermata');
    });

    test('rejects a config missing the package id', () {
      // The id is how Obtainium tells "the app I am tracking" from "a different
      // app with the same display name", so a config without it silently tracks
      // nothing useful.
      expect(
        () => ObtainiumApp.fromJson({
          'url': 'https://github.com/CephandriusMaxtori/Fermata',
          'author': 'CephandriusMaxtori',
          'name': 'Fermata',
        }),
        throwsFormatException,
      );
    });

    test('rejects an empty required field', () {
      expect(
        () => ObtainiumApp.fromJson({
          'id': 'com.hoid.fermata',
          'url': '',
          'author': 'CephandriusMaxtori',
          'name': 'Fermata',
        }),
        throwsFormatException,
      );
    });

    test('rejects a non-string field rather than coercing it', () {
      expect(
        () => ObtainiumApp.fromJson({
          'id': 42,
          'url': 'https://github.com/CephandriusMaxtori/Fermata',
          'author': 'CephandriusMaxtori',
          'name': 'Fermata',
        }),
        throwsFormatException,
      );
    });
  });

  group('addLink', () {
    test('is an obtainium:// deep link carrying the config', () {
      final link = _config.addLink;

      expect(link.scheme, 'obtainium');
      expect(link.host, 'app');
    });

    test('round-trips: decoding the payload gives the config back', () {
      // Obtainium shows this payload to the user before importing it, so it has
      // to survive percent-encoding unchanged.
      final encoded = _config.addLink.path.substring(1);
      final decoded = jsonDecode(Uri.decodeComponent(encoded)) as Map<String, Object?>;

      expect(decoded['id'], 'com.hoid.fermata');
      expect(decoded['name'], 'Fermata');
      expect(decoded['url'], 'https://github.com/CephandriusMaxtori/Fermata');
    });

    test('leaves no unencoded JSON punctuation in the path', () {
      // A raw `{` or `"` in a deep-link path is what makes Android reject the
      // intent, so this asserts the encoding rather than trusting it.
      final path = _config.addLink.path;
      expect(path, isNot(contains('{')));
      expect(path, isNot(contains('"')));
      expect(path, contains('%7B'));
    });

    test('serialises fields in a fixed order', () {
      // Obtainium's confirmation dialog shows the raw JSON. Decoding a map would
      // order the keys differently and make that dialog unreviewable between
      // runs.
      expect(_config.toJson().indexOf('"id"'), lessThan(_config.toJson().indexOf('"url"')));
      expect(_config.toJson().indexOf('"url"'), lessThan(_config.toJson().indexOf('"author"')));
      expect(_config.toJson().indexOf('"author"'), lessThan(_config.toJson().indexOf('"name"')));
    });
  });

  group('refreshLink', () {
    test('targets the app by package id', () {
      final link = _config.refreshLink;

      expect(link.scheme, 'obtainium');
      expect(link.host, 'refresh');
      expect(link.queryParameters['id'], 'com.hoid.fermata');
    });
  });
}
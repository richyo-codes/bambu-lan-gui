import 'help_catalog.dart';

const defaultHelpEntries = <HelpEntry>[
  HelpEntry(
    id: 'firmware-release-notes',
    title: 'Check firmware release notes',
    summary:
        'Firmware updates can change LAN, MQTT, camera, light control, and file-transfer behavior.',
    category: HelpCategory.firmware,
    matchPhrases: ['firmware', 'release notes', 'update', 'compatibility'],
    suggestedFixes: [
      'Review the printer firmware release notes before troubleshooting a new issue.',
      'Compare current behavior with known firmware changelogs.',
      'Older firmware may report different chamber light and nozzle metadata.',
    ],
    links: [
      HelpLink(
        label: 'Bambu firmware release history',
        url:
            'https://wiki.bambulab.com/en/x1/manual/X1-X1C-AMS-firmware-release-history',
      ),
    ],
  ),
  HelpEntry(
    id: 'mqtt-unauthorized',
    title: 'MQTT authentication failed',
    summary: 'The printer rejected the local LAN credentials or access code.',
    category: HelpCategory.troubleshooting,
    matchCodes: ['401', 'unauthorized', 'access denied'],
    matchPhrases: [
      'unauthorized',
      'check special code',
      'credentials',
      'access code',
    ],
    suggestedFixes: [
      'Confirm LAN mode is enabled on the printer.',
      'Re-enter the printer access code.',
      'Check that the printer IP still matches the current network lease.',
    ],
  ),
  HelpEntry(
    id: 'mqtt-forbidden',
    title: 'Printer access blocked',
    summary: 'The printer or local network rejected the control request.',
    category: HelpCategory.troubleshooting,
    matchCodes: ['403', 'forbidden'],
    matchPhrases: ['forbidden', 'access forbidden', 'blocked'],
    suggestedFixes: [
      'Verify the printer is reachable on the LAN.',
      'Check firewall rules between the app and printer.',
      'Confirm the printer is in the expected remote-control mode.',
    ],
  ),
  HelpEntry(
    id: 'stream-timeout',
    title: 'Stream timed out',
    summary: 'The printer stream did not respond quickly enough.',
    category: HelpCategory.troubleshooting,
    matchCodes: ['timeout', 'timed out'],
    matchPhrases: [
      'timed out',
      'timeout',
      'connection timed out',
      'unreachable',
    ],
    suggestedFixes: [
      'Confirm the printer is on the same network segment.',
      'Check the stream port and protocol.',
      'Retry after reconnecting the printer if it just woke from sleep.',
    ],
  ),
  HelpEntry(
    id: 'stream-host-not-found',
    title: 'Printer host not found',
    summary: 'The configured printer IP or hostname could not be resolved.',
    category: HelpCategory.troubleshooting,
    matchCodes: ['host not found', 'resolve'],
    matchPhrases: ['host not found', 'could not resolve', 'dns'],
    suggestedFixes: [
      'Recheck the configured printer IP address.',
      'Renew the printer network lease if the IP changed.',
      'Use a DHCP reservation for the printer if possible.',
    ],
  ),
  HelpEntry(
    id: 'stream-refused',
    title: 'Connection refused',
    summary:
        'The target service is reachable, but the requested port is closed.',
    category: HelpCategory.troubleshooting,
    matchCodes: ['connection refused', 'refused'],
    matchPhrases: ['connection refused', 'refused', 'service not available'],
    suggestedFixes: [
      'Check whether the printer supports the requested feature.',
      'Verify the port number matches the selected printer profile.',
      'Confirm firewall or router rules are not blocking the service.',
    ],
  ),
  HelpEntry(
    id: 'stream-tls',
    title: 'TLS or certificate problem',
    summary:
        'The connection failed during encryption or certificate validation.',
    category: HelpCategory.troubleshooting,
    matchCodes: ['tls', 'ssl', 'certificate'],
    matchPhrases: ['tls', 'ssl', 'certificate', 'bad cert'],
    suggestedFixes: [
      'Check whether the printer expects RTSPS or plain RTSP.',
      'Verify the printer CA certificate if you are enforcing validation.',
      'Try the connection with the printer profile’s default protocol first.',
    ],
  ),
];

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:eureka/api/tencent_asr_s3_client.dart';

void main() {
  test('createPresign parses upload URL and headers', () async {
    final client = TencentAsrS3Client(
      baseUrl: 'https://pre.card.biz',
      client: MockClient((request) async {
        expect(request.url.path, '/api/platform/speech/tencent_asr/s3_presign');
        return http.Response(
          jsonEncode({
            'code': 0,
            'message': 'success',
            'data': {
              's3_key': '2026/06/12/F1.mp3',
              'upload_url':
                  'https://s3.ap-southeast-1.amazonaws.com/card-biz-file-test/2026/06/12/F1.mp3?AWSAccessKeyId=abc&Signature=def&Expires=1781269087',
              'audio_url':
                  'https://s3.ap-southeast-1.amazonaws.com/card-biz-file-test/2026/06/12/F1.mp3?AWSAccessKeyId=abc&Signature=get&Expires=1781269087',
              'expires_in': 3600,
              'headers': {'Content-Type': 'audio/mpeg'},
            },
          }),
          200,
        );
      }),
    );

    final presign = await client.createPresign(filename: 'F1.mp3');

    expect(presign.s3Key, '2026/06/12/F1.mp3');
    expect(
      presign.uploadUrl,
      'https://s3.ap-southeast-1.amazonaws.com/card-biz-file-test/2026/06/12/F1.mp3?AWSAccessKeyId=abc&Signature=def&Expires=1781269087',
    );
    expect(
      presign.audioUrl,
      'https://s3.ap-southeast-1.amazonaws.com/card-biz-file-test/2026/06/12/F1.mp3?AWSAccessKeyId=abc&Signature=get&Expires=1781269087',
    );
    expect(presign.headers, {'Content-Type': 'audio/mpeg'});
    expect(presign.expiresIn, 3600);
  });
}

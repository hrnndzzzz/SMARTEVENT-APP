import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String url =
      'https://vzdctweadahekptsmnyn.supabase.co';

  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6ZGN0d2VhZGFoZWtwdHNtbnluIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NjU0MjQwNiwiZXhwIjoyMTAyMTE4NDA2fQ.mQbnp3LqOsCo_pHdijd3fpWT6pgEhmi6IF3jUMbRRYo';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
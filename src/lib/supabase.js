import { createClient } from '@supabase/supabase-js';

// A URL e a publishable key são próprias para uso no navegador.
// Nunca coloque a chave secret/service_role neste arquivo.
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || 'https://wdiyjaoydzdcvtgjowog.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || 'sb_publishable_u3-82P_5WXG-8BfgLibPDw__Itf5Co1';

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
export const isSupabaseConfigured = true;

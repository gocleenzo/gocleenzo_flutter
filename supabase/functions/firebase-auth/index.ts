import { createClient, type User } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const VALID_ROLES = ['customer', 'worker']

// ── Normalize phone to E.164 format: +919XXXXXXXXX ──────────────
function normalizePhone(raw: string): string {
  // Strip all non-digits
  let digits = raw.replace(/\D/g, '')
  // Remove leading 91 if 12 digits (919XXXXXXXXX → 9XXXXXXXXX)
  if (digits.length === 12 && digits.startsWith('91')) {
    digits = digits.slice(2)
  }
  // Should now be 10 digits
  return `+91${digits}`
}

// ── Find an auth user by phone, paginating through ALL pages ────
// (admin.listUsers() only returns one page — default 50 rows —
// so a single-page search silently misses users past that page,
// which is what caused "Phone number already registered".)
async function findAuthUserByPhone(
  // deno-lint-ignore no-explicit-any
  supabaseAdmin: any,
  phone: string,
): Promise<User | null> {
  const bare = phone.replace('+', '')
  const perPage = 1000
  let page = 1

  while (true) {
    const { data, error } = await supabaseAdmin.auth.admin.listUsers({ page, perPage })
    if (error) {
      console.error('listUsers error:', error)
      return null
    }

    const users: User[] = data?.users ?? []
    const match = users.find((u) => u.phone === phone || u.phone === bare)
    if (match) return match

    if (users.length < perPage) return null // no more pages
    page += 1
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // ── role is REQUIRED now ──────────────────────────────────────
    // This is what keeps the customer app and worker app from ever
    // resolving to the same `users` row for the same phone number.
    // Each app must explicitly say who it is on every login call —
    // see login_screen.dart in both apps, which now send
    // { firebase_uid, phone, role: 'customer' | 'worker' }.
    const { firebase_uid, phone: rawPhone, role } = await req.json()

    if (!firebase_uid || !rawPhone || !role) {
      return new Response(
        JSON.stringify({ error: 'firebase_uid, phone, and role are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!VALID_ROLES.includes(role)) {
      return new Response(
        JSON.stringify({ error: `role must be one of: ${VALID_ROLES.join(', ')}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ── Always normalize to +91XXXXXXXXXX ───────────────────────
    const phone = normalizePhone(rawPhone)
    console.log(`Phone normalized: ${rawPhone} → ${phone}, role: ${role}`)

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // ── Step 1: Find existing user in users table ────────────────
    // Matched by (phone, role) — NOT phone alone. This is the fix:
    // the same phone number can have a separate 'customer' row and a
    // separate 'worker' row, and this lookup only ever returns the
    // one that matches the app asking. Backed by the
    // users_phone_role_unique constraint at the DB level, so this can
    // never accidentally return (or create) more than one row per
    // (phone, role) pair.
    const { data: existingUser } = await supabaseAdmin
      .from('users')
      .select('id, full_name, role')
      .eq('phone', phone)
      .eq('role', role)
      .maybeSingle()

    if (!existingUser) {
      // Brand new user for THIS role — signal the app to collect a
      // name (even if this same phone already has a row under the
      // OTHER role — that's expected and fine, they're independent).
      console.log(`New ${role} user:`, phone)
      return new Response(
        JSON.stringify({ is_new_user: true }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // userId is THE canonical id for this app — every foreign key
    // (bookings.customer_id, addresses.user_id, etc.) points at this
    // exact value. It must never be changed and must always be what
    // we return to the client.
    const userId = existingUser.id
    console.log(`Existing ${role} user found:`, userId)

    // ── Step 2: Best-effort auth.users bookkeeping (non-authoritative) ──
    // This exists only to keep a matching auth.users row around for
    // admin/dashboard purposes. It must NEVER influence what gets
    // returned to the client — userId (the public.users row) is
    // always the source of truth returned below.
    //
    // IMPORTANT: we deliberately do NOT rewrite public.users.id to
    // match an auth.users id anymore. That update was the root cause
    // of a real bug: users.id is referenced by foreign keys elsewhere
    // (addresses, bookings, etc.), so Postgres silently rejected the
    // primary-key change — but the old code never checked the update's
    // error, so it still returned the new (non-existent-in-users)
    // id to the client. The client would then fail to find that user
    // and log itself out, bouncing back to /login right after a
    // successful login.
    //
    // NOTE: auth.users has its own phone-uniqueness behaviour, and
    // now that ONE phone number can map to TWO public.users rows
    // (customer + worker), this bookkeeping call can only ever attach
    // one auth.users row per phone anyway. That's fine — this block
    // is purely cosmetic/admin-dashboard convenience and never affects
    // what's returned to either app.
    try {
      const { data: authData } = await supabaseAdmin.auth.admin.getUserById(userId)

      if (!authData?.user) {
        const existingAuthByPhone = await findAuthUserByPhone(supabaseAdmin, phone)

        if (!existingAuthByPhone) {
          // No auth user anywhere for this phone — create one under
          // the same id as the profile so they stay in sync going
          // forward. If this fails, it's harmless — it doesn't
          // affect the response.
          const { error: authError } = await supabaseAdmin.auth.admin.createUser({
            id:            userId,
            phone:         phone,
            phone_confirm: true,
            user_metadata: { firebase_uid, role },
          })
          if (authError) {
            console.warn('createUser (non-fatal, cosmetic only):', authError.message)
          } else {
            console.log('Created auth user for bookkeeping:', userId)
          }
        } else {
          console.log(
            'Auth user exists under a different id — leaving as-is ' +
            '(not rewriting users.id):', existingAuthByPhone.id
          )
        }
      } else {
        console.log('Auth user already exists:', authData.user.id)
      }
    } catch (bookkeepingErr) {
      console.warn('Auth bookkeeping error (non-fatal):', bookkeepingErr)
    }

    // ── Step 3: Return the real profile info — always ────────────
    return new Response(
      JSON.stringify({
        is_new_user: false,
        user_id:     userId,
        full_name:   existingUser.full_name,
        role:        existingUser.role,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Edge function error:', error)
    const message = error instanceof Error ? error.message : 'Unknown error'
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
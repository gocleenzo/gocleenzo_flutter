import { createClient, type User } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

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
    const { firebase_uid, phone: rawPhone } = await req.json()

    if (!firebase_uid || !rawPhone) {
      return new Response(
        JSON.stringify({ error: 'firebase_uid and phone are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ── Always normalize to +91XXXXXXXXXX ───────────────────────
    const phone = normalizePhone(rawPhone)
    console.log(`Phone normalized: ${rawPhone} → ${phone}`)

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // ── Step 1: Find existing user in users table ────────────────
    const { data: existingUser } = await supabaseAdmin
      .from('users')
      .select('id, full_name, role')
      .eq('phone', phone)
      .maybeSingle()

    if (!existingUser) {
      // Brand new user — signal Flutter to collect name
      console.log('New user:', phone)
      return new Response(
        JSON.stringify({ is_new_user: true }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const userId = existingUser.id
    console.log('Existing user found:', userId)

    // ── Step 2: Check if auth user exists with this userId ───────
    const { data: authData } = await supabaseAdmin.auth.admin.getUserById(userId)
    let supabaseUserId = userId

    if (!authData?.user) {
      // ── Auth user missing under this ID — search ALL pages by
      // phone first, to avoid creating a duplicate ──────────────
      const existingAuthByPhone = await findAuthUserByPhone(supabaseAdmin, phone)

      if (existingAuthByPhone) {
        // Auth user exists but with a different ID — sync it
        supabaseUserId = existingAuthByPhone.id
        console.log('Auth user found by phone:', supabaseUserId)

        if (supabaseUserId !== userId) {
          await supabaseAdmin
            .from('users')
            .update({ id: supabaseUserId })
            .eq('phone', phone)
        }
      } else {
        // Truly no auth user — create one
        try {
          const { data: newAuthUser, error: authError } =
            await supabaseAdmin.auth.admin.createUser({
              phone:         phone,        // keep the + prefix
              phone_confirm: true,
              user_metadata: { firebase_uid },
            })

          if (authError) throw authError

          supabaseUserId = newAuthUser.user.id
          console.log('Created new auth user:', supabaseUserId)

          await supabaseAdmin
            .from('users')
            .update({ id: supabaseUserId })
            .eq('phone', phone)
        } catch (createErr) {
          // Race condition fallback: an auth user was created for
          // this phone between our search and this create call.
          const msg = createErr instanceof Error ? createErr.message : String(createErr)
          console.warn('createUser failed, re-checking by phone:', msg)

          const retryMatch = await findAuthUserByPhone(supabaseAdmin, phone)
          if (!retryMatch) {
            // Genuinely unrecoverable — surface the original error
            throw createErr
          }

          supabaseUserId = retryMatch.id
          console.log('Recovered existing auth user after race:', supabaseUserId)

          if (supabaseUserId !== userId) {
            await supabaseAdmin
              .from('users')
              .update({ id: supabaseUserId })
              .eq('phone', phone)
          }
        }
      }
    } else {
      console.log('Auth user already exists:', authData.user.id)
      supabaseUserId = authData.user.id
    }

    // ── Step 3: Clean up orphan auth rows for this phone ─────────
    // Delete any auth.users rows that have email = *@cleenzo.app
    // and phone = null (the duplicate magic-link rows)
    try {
      const { data: allUsers } = await supabaseAdmin.auth.admin.listUsers({ perPage: 1000 })
      const orphans = allUsers?.users?.filter(
        (u: User) =>
          u.id !== supabaseUserId &&
          u.email?.endsWith('@cleenzo.app') &&
          !u.phone
      ) ?? []

      for (const orphan of orphans) {
        // Only delete if it was created for THIS user
        if (orphan.email === `${supabaseUserId}@cleenzo.app` ||
            orphan.email === `${userId}@cleenzo.app`) {
          console.log('Deleting orphan auth row:', orphan.id)
          await supabaseAdmin.auth.admin.deleteUser(orphan.id)
        }
      }
    } catch (cleanupErr) {
      console.warn('Cleanup error (non-fatal):', cleanupErr)
    }

    // ── Step 4: Return user info ──────────────────────────────────
    return new Response(
      JSON.stringify({
        is_new_user: false,
        user_id:     supabaseUserId,
        full_name:   existingUser.full_name,
        role:        existingUser.role ?? 'customer',
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
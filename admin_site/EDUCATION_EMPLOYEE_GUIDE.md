# Education setup for employees

## Before setup

Confirm the school/class name, teacher's email, student count, and access end date. Teachers and students can create their Mixroom accounts after receiving invitations.

## Create the school in admin

1. Sign into admin.mixroom.ai with an employee account authorized to edit team records.
2. Open Admin controls → Team records → Create education account.
3. Enter the school/class name, student seats, teacher email, and access period. Leave Teacher user ID blank for an email invitation. To activate an existing account directly, enter its actual ID and email or click Use selected teacher.
4. Click **Set up class**. The class is ready immediately; teacher access remains pending until acceptance.
5. For a class saved by a failed attempt, select it in the table, open Existing school, click Use selected school, then Set up class. This reuses the class and pending invitation.
6. Check the email result. If delivery fails, use **Resend teacher email** or **Copy teacher link**. Do not create another school to retry an email.
7. Select the school and invite students, even before the teacher accepts.

## Teacher activation

The email includes Open in Mixroom, an invitation code, and a website signup/sign-in link. The teacher creates an account or signs in with the exact invited email and verifies their email when prompted. If the app link does not open, paste the code into Account → Subscription → Education invite and accept. The website can also accept the pending invitation after authentication. The account receives the teacher role and class dashboard access without consuming a student seat.

If needed, the teacher can paste the link in Mixroom → Account → Subscription → Education invite and accept there. Access ends at the class deadline; accepting later does not restart the period.

## Set the access period

- **One-day class:** choose Days → 1 for exactly 24 hours from provisioning. If setting up before the class, choose the specific date and time the class access should end.
- **Longer course:** enter the number of days or calendar months. Calendar months keep the same day of the month where possible and clamp to the last day of shorter months.
- **Specific date:** choose the exact end date and time. The form uses your browser's local timezone and shows the resolved end time. The API stores UTC timestamps.
- **No end date:** access continues until an employee sets a deadline or revokes access. Existing organizations keep this behavior unless edited.

These are one-time access grants, not automatic monthly billing. Periods begin when saved, not when a student accepts an invitation. A late signup does not restart the period.

The class end date applies to the teacher and all student seats. In the invitation form, leave **Same as class** selected unless a group needs a shorter period. Review locks the chosen student deadline for that batch. Existing pending invitations retain their original deadline when resent.

To change an existing class period, select it → **Edit organization record → Access period → Save**. To change one student's period, select their membership → **Edit membership record → Access period → Save**. Student access always stops at the earlier of the student and class deadlines. Extending the class extends inherited seats, but does not extend custom student deadlines.

For individually granted plans, use Users → **Grant paid access → Access period**. The same days/months/date choices apply to every plan; a team grant also sets the team's deadline.

After expiry, server access checks stop granting that plan's benefits. Accounts and project records are not deleted by this feature. Existing paid personal plans continue according to their own terms.

## Share one education code without student emails

1. Select the Education class in admin.mixroom.ai.
2. In **Education invite code**, click **Generate code**, then **Copy code**. Existing class links already have a code; select the class to see it.
3. Share the same 10-character code with all students through your usual channel. Students can type lowercase and omit the hyphen. **Copy link** remains available as an alternative.
4. Students sign into their own Mixroom accounts, open **Account → Subscription → Education invite**, paste the code, and click **Accept**. The code works even if the box says “Paste invite link.”

Generating a link does not send email or reserve seats. Students use one seat when they join; repeat acceptance does not consume another. Existing pending student email invitations can be accepted through the shared link without reserving another seat. Joining stops when the class is full, inactive, expired, or the link is revoked. A removed or expired student's access requires the teacher to restore it.

**Revoke code & link** prevents further use of both the code and link and preserves current students. Generate again after revocation to issue a different link. Individual email invitations remain available below.

Teacher website and native app controls have been implemented in source but are not published in this release. Use the employee admin dashboard to generate links for now.

## Invite the class from admin

1. Select the school in the organization table. Open **Invite students** above the provisioning form.
2. Paste a column of email addresses from your spreadsheet. Newlines, spaces, commas, and semicolons work. Paste emails only, without names or a header. Each batch supports up to 500 addresses; use multiple batches for larger classes.
3. Choose English or Korean for the invitation emails and leave **Same as class** selected, or choose a shorter student access period.
4. Click **Review emails**. This does not send mail or reserve seats. The review removes duplicate emails, flags invalid addresses, identifies active students and pending invitations, and checks available seats.
5. Correct invalid emails or increase the seat limit if needed, then review again.
6. Click **Send invites**. Keep the page open while each student’s result appears. This sends real email and reserves one seat per new invitation. Existing active students, staff, and pending invitations are skipped.
7. Use **Retry failed** after a failure. An uncertain request retries by checking for an existing invitation first. If it already exists, use **Resend email** explicitly. Resending uses the same link and reserved seat.
8. For a missing email, use **Copy link** to share that student's link, or **Resend email** on a pending invitation. A suppressed address needs attention; do not keep retrying it.

The results stay on this page during the session. To find invitations after a reload, paste and review the same roster again. Pending rows include Copy link and Resend email. “Email sent” means the email provider accepted the request, not confirmed inbox delivery.

## Student activation and teacher checks

1. The student creates an account or signs in using the exact invited email and verifies their email if prompted.
2. In Mixroom, open account/subscription → Education invite, paste the invitation code or link, and click **Accept**.
3. Check for “Education student seat activated.”
4. The teacher opens account/subscription → View Dashboard → Students to confirm the student is Active. Pending means the seat is reserved but acceptance is incomplete.

Test one student before inviting the full class. Check email delivery, signup, acceptance, and app access. Website acceptance requires a separate live check; the app supports pasting the link directly. The teacher can also invite students individually from their dashboard.

## Manage the class

- **Missing email:** the teacher opens Students → Copy link and shares that student's link with them.
- **Wrong invited email:** cancel the pending invitation and invite the correct email. Students cannot accept another email's invitation.
- **Student leaves:** use Remove in the teacher dashboard to release the seat.
- **Need more seats:** in admin, select the organization → Edit organization record → Seat limit → Save. The count must cover active and pending seats.
- **Reduce seats:** first cancel unused invitations or remove departed students. Then save the lower count.

Do not use a zero seat limit for Education. A positive count keeps the class capacity explicit.

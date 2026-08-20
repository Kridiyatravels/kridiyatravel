-- Exact capture of three production objects that were created outside the
-- timestamped migration chain. Production already contains these objects; this
-- file exists so a clean rebuild reaches the same state.

CREATE SEQUENCE IF NOT EXISTS "public"."doc_receipt_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE "public"."doc_receipt_seq" OWNER TO "postgres";

CREATE OR REPLACE TRIGGER "staff_permissions_set_updated_at"
BEFORE UPDATE ON "public"."staff_permissions"
FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE POLICY "payments_select_customer_own"
ON "public"."payments"
FOR SELECT
TO "authenticated"
USING (
  (
    "payment_direction" = 'customer_in'::"text"
  )
  AND (
    EXISTS (
      SELECT 1
      FROM "public"."bookings" "b"
      WHERE "b"."id" = "payments"."booking_id"
        AND "b"."user_id" = (SELECT "auth"."uid"() AS "uid")
        AND "b"."archived_at" IS NULL
    )
    OR EXISTS (
      SELECT 1
      FROM "public"."enquiries" "e"
      WHERE "e"."id" = "payments"."enquiry_id"
        AND "e"."user_id" = (SELECT "auth"."uid"() AS "uid")
    )
  )
);

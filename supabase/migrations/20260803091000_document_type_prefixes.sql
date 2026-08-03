-- Add the two document types that now have templates but no number prefix.
--
-- set_document_number() assigns a prefixed, sequenced number per document
-- type and falls through to 'DOC' for anything it does not recognise. The
-- supplier payment note and the monthly company statement both fell through,
-- so they would have been numbered DOC-2026-nnnn and shared the invoice
-- sequence with unrelated documents.
--
-- NOT YET APPLIED. Review, then apply with the backend session's tooling.

create sequence if not exists public.doc_statement_seq;

create or replace function public.set_document_number()
returns trigger
language plpgsql
as $function$
declare
  yr text := to_char(now(), 'YYYY');
  prefix text;
  seq_name text;
begin
  if new.document_number is not null and new.document_number <> '' then
    return new;
  end if;
  case new.document_type
    when 'invoice' then prefix := 'INV'; seq_name := 'public.doc_invoice_seq';
    when 'eticket' then prefix := 'ETK'; seq_name := 'public.doc_eticket_seq';
    when 'cancellation' then prefix := 'CXL'; seq_name := 'public.doc_cancellation_seq';
    when 'visa_rejection' then prefix := 'REJ'; seq_name := 'public.doc_rejection_seq';
    when 'receipt' then prefix := 'RCT'; seq_name := 'public.doc_receipt_seq';
    when 'payment_request' then prefix := 'PAY'; seq_name := 'public.doc_receipt_seq';
    when 'refund_note' then prefix := 'RFN'; seq_name := 'public.doc_receipt_seq';
    when 'quotation' then prefix := 'QTN'; seq_name := 'public.doc_invoice_seq';
    when 'hotel_voucher' then prefix := 'HTL'; seq_name := 'public.doc_eticket_seq';
    when 'visa_confirmation' then prefix := 'VSA'; seq_name := 'public.doc_eticket_seq';
    when 'corporate_confirmation' then prefix := 'COR'; seq_name := 'public.doc_eticket_seq';
    -- New below this line.
    when 'supplier_payment_note' then prefix := 'SPN'; seq_name := 'public.doc_invoice_seq';
    when 'monthly_statement' then prefix := 'STM'; seq_name := 'public.doc_statement_seq';
    else prefix := 'DOC'; seq_name := 'public.doc_invoice_seq';
  end case;
  new.document_number := prefix || '-' || yr || '-' || lpad(nextval(seq_name)::text, 4, '0');
  return new;
end;
$function$;

-- The statement gets its own sequence rather than sharing the invoice one:
-- a company reading STM-2026-0001 through STM-2026-0012 should see twelve
-- consecutive months, not numbers with gaps where invoices were issued.

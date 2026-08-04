-- The documents insert trigger must allocate numbers as its postgres owner.
-- Keep sequence privileges unavailable to authenticated users so they cannot
-- advance document-number sequences without creating a document.
alter function public.set_document_number() security definer;

-- Pin name resolution for the privileged trigger function.
alter function public.set_document_number() set search_path to 'public';

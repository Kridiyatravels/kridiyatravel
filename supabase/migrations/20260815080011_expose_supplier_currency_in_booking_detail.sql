-- The staff booking screen needs the supplier currency to record supplier-side
-- payments accurately when it differs from the customer-facing sale currency.
do $migration$
declare
  current_definition text;
  updated_definition text;
begin
  select pg_get_functiondef(
    'public.get_operations_booking_detail(uuid)'::regprocedure
  ) into current_definition;

  updated_definition := replace(
    current_definition,
    '''supplier_reference'', b.supplier_reference,',
    '''supplier_reference'', b.supplier_reference,' || chr(10) ||
      '      ''supplier_currency'', b.supplier_currency,'
  );

  if updated_definition = current_definition then
    raise exception 'Could not locate supplier_reference in get_operations_booking_detail';
  end if;

  execute updated_definition;
end;
$migration$;

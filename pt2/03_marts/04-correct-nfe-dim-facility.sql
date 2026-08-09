use role candidate_callahan;
use schema callahan_db.marts;

/*
DATA CONFLICT

On: NET_FUNDS_EMPLOYED

Between: FACTORVIEW system and TENOR system

Resolution: Defer to TENOR's FACILITY_BALANCE field unless the facility in question
            is not found in the Tenor data

Rationale:
  - The fund descriptions between Tenor and Factorview differ only in a superficial sense,
    (e.g. 'Cardinal ABL & Factoring Fund' from Factorview and 'ABL Fund' from Tenor), so
    it seems likely that these systems are in fact referring to the same fund and just
    using different verbiage

  - Which fund is tied to which facility should be most authoratatively determined by the
    Loan Servicing platform, since that's where the source-of-truth for all loans (and
    the funds they are tied to) lives.

  - The fund descriptions from Factorview are also generally more detailed than the
    ones from Tenor
*/

create or replace view v_facility_nfe as
select f.facility_sk
      ,f.facility_balance * -1 as net_funds_employed
from v_fact_transaction f
where f.facility_sk <> md5('NULL FACILITY')
-- do not set NFE for unknown facilities
qualify row_number() over (
        partition by f.facility_sk
        order     by f.transaction_date desc
      ) = 1;


update dim_facility tgt
set tgt.net_funds_employed = src.net_funds_employed
from v_facility_nfe src
where tgt.facility_sk = src.facility_sk
  and tgt.is_current_ind
;

select * from dim_facility
order by facility_id;

-- A sent proposal goes to the Moderator and the Dean before the SDS Office,
-- and a returned one says who returned it.
BEGIN;
ALTER TABLE public.sap_proposals DROP CONSTRAINT sap_proposals_state_check;
ALTER TABLE public.sap_proposals ADD CONSTRAINT sap_proposals_state_check
    CHECK (state IN ('draft','pending_department_review','pending_sap_review','revision_requested','sds_signed','approved','completed','rejected'));
ALTER TABLE public.sap_proposals ADD COLUMN returned_by varchar(10)
    CONSTRAINT sap_proposals_returned_by_check CHECK (returned_by IN ('moderator','dean','sds'));
-- Until now only the SDS Office could return a proposal.
UPDATE public.sap_proposals SET returned_by = 'sds' WHERE state = 'revision_requested';
COMMIT;

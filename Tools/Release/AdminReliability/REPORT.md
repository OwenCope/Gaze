# Admin reliability checkpoint

The current website sources are preserved in files/ with SHA-256 values in
SOURCES.json. They include serialized settings/tester/role requests, acknowledgement
validation, retained drafts and rollback on failures, field labels, confirmations,
and reduced-motion support for the shared admin modal.

Earlier in this session, test-contracts.cjs passed 65 checks and the actual-component
browser fixture passed 23 recovery, duplicate-request and confirmation cases.
The final browser failure was a premature fixed animation wait; changing the driver
to wait for the expected state resolved it. These results use synthetic requests
and data, not a live administrator account, Blob service or email provider.

The integrated website production builds include these sources. The subsequent
whole-site layout pass changes admin navigation, surfaces and editing controls;
its current build and browser results are recorded in ../SecondaryPages/REPORT.md.
No production service or data was changed. The separately stopped account-menu
and release-gallery behavior tasks were not resumed by this pass.

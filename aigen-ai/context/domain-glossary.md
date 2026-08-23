# Domain glossary

| Term | Meaning | Status/evidence |
|---|---|---|
| Aigen | Full procurement application implemented by the three repositories | **Verified** |
| PR | Purchase Request imported from SAP-derived iSearch data | **Verified:** importer/query names |
| RFQ | Request for Quotation sent to one or more vendors | **Verified:** routes/models/UI |
| QCF | Quotation Comparison Form reviewed by CL and sometimes Management | **Verified:** routes/models/UI |
| CS | Internal sourcing role handling RFQ exceptions and progression | **Verified role; Unknown expansion** |
| CL | Internal approval/leader role for QCF | **Verified role; Unknown expansion** |
| DIC | Internal user/confirmation role for quotation items | **Verified role; Unknown expansion** |
| Management | Optional QCF approval role controlled by configuration/policy | **Verified** |
| Vendor | External quotation participant, commonly accessing a token link | **Verified** |
| iSearch / PRPO | Schema/application surface containing SAP-derived `search_library` PR data | **Verified** |
| iSourcing / task board | Schema/application surface containing users and board/card workflow data | **Verified** |
| BCG | Server/business group with import value behavior distinct from GEMS | **Verified identifier; Unknown expansion** |
| GEMS | Server/business group with `value_idr` rules and a manual-PO pilot flag | **Verified identifier; Unknown expansion** |
| Auto PO | Configuration/flow that determines automated purchase-order handling and SAP sync | **Verified; exact policy is runtime-configured** |
| Manual sourcing | A path used when assignment/vendor criteria do not support automated import or when workflow actors send work to iSourcing | **Verified** |
| Material hierarchy | Material group → extended material group → material number structure | **Verified** |
| Material assignment | Vendor/category assignment attached to a hierarchy level | **Verified** |
| Category matrix | Mapping from categories to procurement users/PICs | **Verified** |
| PIC | Person in charge/assigned procurement user | **Inferred from repository documentation** |
| Milestone/submilestone | Persisted workflow-position identifiers used to drive status/actions | **Verified** |
| Vendor batch | Number identifying quotation/vendor rounds within an RFQ | **Verified; detailed rollover rules Unknown** |
| Surrogate | CS-entered quotation/evidence path on behalf of a vendor | **Inferred from route/component names** |
| OE | Price/reference value used in mismatch and revision workflow | **Verified identifier; exact expansion Unknown** |
| SLA | Elapsed-time tracking for workflow stages, often in business days | **Verified** |
| `pr_library` | Transient Aigen staging table populated by the import worker | **Verified** |
| `rfq_library` | Main RFQ line-item persistence used by backend and importer | **Verified** |
| `search_library` | iSearch snapshot read by the importer | **Verified** |
| Server group | Runtime partition such as BCG or GEMS affecting rules/config | **Verified** |


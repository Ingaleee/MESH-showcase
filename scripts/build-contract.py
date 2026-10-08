"""Author the checked-in OpenAPI contract. Output is deterministic JSON."""
import json
import sys
from pathlib import Path


def reference(name):
    return {"$ref": f"#/components/schemas/{name}"}


def obj(properties, required=None):
    return {
        "type": "object",
        "properties": properties,
        "required": list(properties) if required is None else required,
        "additionalProperties": False,
    }


def array(item):
    return {"type": "array", "items": item}


def nullable(schema):
    return {"anyOf": [schema, {"type": "null"}]}


string = {"type": "string"}
integer = {"type": "integer"}
boolean = {"type": "boolean"}
identifier = {"type": "string", "format": "uuid"}
schemas = {}
schemas["Account"] = obj({
    "id": identifier, "display_name": string,
    "persona": {"type": "string", "enum": ["client", "creator"]},
    "email": {"type": "string", "format": "email"}, "operator": boolean,
}, ["id", "display_name", "persona"])
schemas["Session"] = obj({"account": nullable(reference("Account")), "csrf_token": string})
schemas["Error"] = obj({
    "code": string, "message": string, "request_id": string,
    "details": {"type": "object", "additionalProperties": True},
}, ["code", "message", "request_id"])
brief_fields = {
    "expected_result": {"type": "string", "maxLength": 3000},
    "deliverables": {"type": "array", "maxItems": 20, "items": {"type": "string", "minLength": 1, "maxLength": 500}},
    "requirements": {"type": "array", "maxItems": 20, "items": {"type": "string", "minLength": 1, "maxLength": 500}},
    "skills": {"type": "array", "maxItems": 20, "items": {"type": "string", "minLength": 1, "maxLength": 80}},
    "reference_urls": {"type": "array", "maxItems": 10, "items": {"type": "string", "format": "uri", "pattern": "^https?://", "maxLength": 2048}},
}
schemas["Project"] = obj({
    "id": identifier, "title": string, "description": string, "category": string,
    "budget_minor": integer, "currency": string, "deadline": {"type": "string", "format": "date"},
    "state": {"type": "string", "enum": ["open", "awarded", "closed"]},
    "accepting_proposals": boolean,
    "brief_version": integer, "lock_version": integer,
    "created_at": {"type": "string", "format": "date-time"}, "client": reference("Account"),
    **brief_fields,
})
schemas["BriefUpdate"] = obj({"version": integer, "created_at": {"type": "string", "format": "date-time"}, "changed_fields": array(string)})
schemas["ProjectDetail"] = obj({"project": reference("Project"), "proposals": array(reference("Proposal")), "proposal_count": integer, "next_proposal_cursor": nullable(string), "matched_proposal_count": integer, "current_proposal_count": integer, "brief_history": array(reference("BriefUpdate")), "owner_context": nullable(reference("OwnerContext"))})
schemas["OwnerContext"] = obj({
    "award": nullable(obj({"proposal_id": identifier, "engagement_id": identifier, "engagement_state": string, "creator_name": string, "created_at": {"type": "string", "format": "date-time"}})),
    "events": array(obj({"id": string, "kind": {"type": "string", "enum": ["published", "brief_revised", "proposal_received", "intake_paused", "intake_resumed", "awarded"]}, "created_at": {"type": "string", "format": "date-time"}, "brief_version": nullable(integer), "actor_name": nullable(string)})),
})
schemas["Proposal"] = obj({
    "id": identifier, "price_minor": integer, "delivery_days": integer,
    "message": string, "brief_version": integer, "creator": reference("Account"),
    "example": nullable(reference("ProposalExample")),
    "created_at": {"type": "string", "format": "date-time"}, "profile": nullable(reference("Profile")),
})
schemas["ProposalExample"] = obj({
    "id": identifier, "filename": string, "byte_size": integer, "content_type": string,
    "state": {"type": "string", "enum": ["quarantined", "available", "rejected"]},
})
schemas["Profile"] = obj({
    "id": identifier, "account_id": identifier, "headline": string, "bio": string,
    "skills": array(string), "rate_minor": integer, "currency": string,
    "accent": string, "account": reference("Account"),
})
term_fields = {
    "title": string, "description": string, "category": string, "budget_minor": integer,
    "currency": string, "deadline": string, "brief_version": integer, "price_minor": integer,
    "delivery_days": integer, "proposal_id": identifier, "commission_basis_points": integer,
    "commission_policy": string,
}
schemas["Terms"] = obj({**term_fields, **brief_fields}, list(term_fields))
schemas["WorkFile"] = obj({"id": identifier, "filename": string, "byte_size": integer, "content_type": string, "sha256": string, "state": {"type": "string", "enum": ["quarantined", "available", "rejected"]}, "submission_id": nullable(identifier)})
schemas["Feedback"] = obj({"id": identifier, "submission_id": nullable(identifier), "kind": {"type": "string", "enum": ["comment", "changes_requested"]}, "content": string, "created_at": {"type": "string", "format": "date-time"}, "actor": reference("Account")})
schemas["Submission"] = obj({"id": identifier, "version": integer, "content": string, "sha256": string, "title": string, "ready_for_acceptance": boolean, "manifest_sha256": nullable(string), "manifest_format": {"type": "string", "enum": ["ordered-json-v0", "canonical-json-v1"]}, "created_at": {"type": "string", "format": "date-time"}, "files": array(reference("WorkFile"))})
schemas["Engagement"] = obj({
    "id": identifier, "client_id": identifier, "creator_id": identifier,
    "state": {"type": "string", "enum": ["agreed", "in_progress", "submitted", "accepted", "cancelled"]},
    "terms": reference("Terms"), "lock_version": integer,
    "submissions_next_cursor": nullable(string), "feedback_next_cursor": nullable(string),
    "submissions": array(reference("Submission")), "accepted_submission_id": nullable(identifier),
    "client": reference("Account"), "creator": reference("Account"), "project_id": identifier,
    "created_at": {"type": "string", "format": "date-time"}, "started_at": nullable({"type": "string", "format": "date-time"}), "accepted_at": nullable({"type": "string", "format": "date-time"}), "feedback": array(reference("Feedback")),
})
schemas["Operation"] = obj({
    "id": identifier, "kind": {"type": "string", "enum": ["fund", "payout"]},
    "state": {"type": "string", "enum": ["requested", "dispatching", "unknown", "confirmed", "failed"]},
    "amount_minor": integer, "currency": string, "scenario": string,
    "external_id": nullable(string), "attempts": integer, "last_error": nullable(string),
})
schemas["Settlement"] = obj({
    "id": identifier, "funded": boolean, "hold": boolean, "hold_reason": nullable(string),
    "amount_minor": integer, "currency": string,
})
schemas["LedgerEntry"] = obj({
    "account_key": string, "currency": string,
    "direction": {"type": "string", "enum": ["debit", "credit"]}, "amount_minor": integer,
})
schemas["Journal"] = obj({
    "id": identifier, "status": string, "description": string,
    "entries": array(reference("LedgerEntry")),
})
schemas["Finance"] = obj({
    "sandbox": boolean, "settlement": nullable(reference("Settlement")),
    "operations": array(reference("Operation")), "ledger": array(reference("Journal")),
})
schemas["Notification"] = obj({
    "id": identifier, "title": string, "body": string, "resource_path": string,
    "read_at": nullable(string), "created_at": string,
})
schemas["PortfolioItem"] = obj({
    "id": identifier, "title": string, "state": string,
    "sha256": nullable(string), "scan_error": nullable(string),
})
schemas["Id"] = obj({"id": identifier})
schemas["VersionedId"] = obj({"id": identifier, "version": integer})
schemas["Operations"] = obj({
    "sandbox": boolean,
    "metrics": obj({key: integer for key in [
        "pending_deliveries", "oldest_delivery_seconds", "processed_deliveries",
        "unknown_payments", "reconciliation_exceptions", "ledger_transactions",
    ]}),
    "payments": array(reference("Operation")),
    "events": array(obj({
        "id": identifier, "event_type": string, "correlation_id": string,
        "aggregate_id": identifier, "created_at": string,
    })),
    "audit": array(obj({
        "id": identifier, "action": string, "resource_id": identifier,
        "correlation_id": string, "created_at": string,
    })),
    "deliveries": array(obj({
        "id": identifier, "state": string, "attempts": integer, "last_error": nullable(string),
    })),
})
project_fields = {
    "title": {"type": "string", "minLength": 1, "maxLength": 160},
    "description": {"type": "string", "minLength": 1, "maxLength": 10000},
    "category": {"type": "string", "enum": ["Тексты", "Дизайн", "Видео", "Разработка", "Маркетинг"]},
    "budget_minor": {"type": "integer", "minimum": 1},
    "currency": {"type": "string", "enum": ["RUB", "USD", "EUR", "JPY"]},
    "deadline": {"type": "string", "format": "date"},
}
project_input = obj({**project_fields, **brief_fields}, list(project_fields))
paths = {}


def endpoint(path, method, operation_id, response, body=None, status=200, authenticated=True, idempotent=False, query=None):
    parameters = []
    for name in ["id", "engagement_id"]:
        if "{" + name + "}" in path:
            parameters.append({"name": name, "in": "path", "required": True, "schema": identifier})
    for name in query or []:
        parameters.append({"name": name, "in": "query", "schema": string})
    if method != "get":
        parameters.append({"name": "X-CSRF-Token", "in": "header", "required": True, "schema": string})
    if idempotent:
        parameters.append({"name": "Idempotency-Key", "in": "header", "required": True, "schema": {"type": "string", "maxLength": 200}})
    responses = {
        str(status): {"description": "Success"},
        **{str(code): {"description": "Domain or access error", "content": {"application/json": {"schema": reference("Error")}}} for code in [400, 401, 403, 404, 409, 422, 429, 500, 503]},
    }
    if response is not None:
        responses[str(status)]["content"] = {"application/json": {"schema": response}}
    value = {
        "operationId": operation_id, "parameters": parameters,
        "security": [{"sessionCookie": []}] if authenticated else [],
        "responses": responses,
    }
    if body:
        value["requestBody"] = {"required": True, "content": {"application/json": {"schema": body}}}
    paths.setdefault(path, {})[method] = value


endpoint("/session", "get", "getSession", reference("Session"), authenticated=False)
endpoint("/session", "post", "signIn", reference("Session"), obj({"session": obj({"email": string, "password": string})}), authenticated=False)
endpoint("/session", "delete", "signOut", reference("Session"))
endpoint("/accounts", "post", "register", reference("Session"), obj({"account": obj({
    "email": string, "display_name": string, "password": {"type": "string", "minLength": 12},
    "persona": {"type": "string", "enum": ["client", "creator"]},
})}), authenticated=False)
for path in ["/session", "/accounts"]:
    paths[path]["post"]["responses"]["429"]["headers"] = {
        "Retry-After": {"description": "Seconds until the shared authentication budget resets.", "schema": {"type": "string", "pattern": "^[1-9][0-9]*$"}},
    }
endpoint("/projects", "get", "listProjects", obj({"data": array(reference("Project")), "next_cursor": nullable(string)}), authenticated=False, query=["q", "category", "cursor", "limit"])
endpoint("/projects", "post", "createProject", reference("Project"), obj({"project": project_input}), status=201, idempotent=True)
endpoint("/projects/{id}", "get", "getProject", reference("ProjectDetail"), authenticated=False, query=["q", "sort", "brief_filter", "ids", "cursor", "limit"])
endpoint("/projects/{id}", "patch", "reviseProject", reference("Project"), obj({"project": project_input, "version": integer}), idempotent=True)
endpoint("/projects/{id}/propose", "post", "submitProposal", reference("Id"), obj({"proposal": obj({
    "price_minor": integer, "delivery_days": integer, "message": string, "brief_version": integer, "example_id": identifier,
}, ["price_minor", "delivery_days", "message", "brief_version"])}), status=201, idempotent=True)
endpoint("/projects/{project_id}/proposal_examples", "post", "uploadProposalExample", reference("ProposalExample"), status=201, idempotent=True)
paths["/projects/{project_id}/proposal_examples"]["post"]["parameters"].append({"name": "project_id", "in": "path", "required": True, "schema": identifier})
paths["/projects/{project_id}/proposal_examples"]["post"]["requestBody"] = {
    "required": True, "content": {"multipart/form-data": {"schema": obj({"file": {"type": "string", "format": "binary"}})}},
}
for method, operation, response, status in [("get", "getProposalExample", reference("ProposalExample"), 200), ("delete", "removeProposalExample", None, 204)]:
    endpoint("/projects/{project_id}/proposal_examples/{id}", method, operation, response, status=status)
    paths["/projects/{project_id}/proposal_examples/{id}"][method]["parameters"].append({"name": "project_id", "in": "path", "required": True, "schema": identifier})
endpoint("/projects/{project_id}/proposal_examples/{id}/download", "get", "downloadProposalExample", None)
paths["/projects/{project_id}/proposal_examples/{id}/download"]["get"]["parameters"].append({"name": "project_id", "in": "path", "required": True, "schema": identifier})
paths["/projects/{project_id}/proposal_examples/{id}/download"]["get"]["responses"]["200"]["content"] = {"application/octet-stream": {"schema": {"type": "string", "format": "binary"}}}
endpoint("/projects/{id}/award", "post", "awardProposal", reference("Id"), obj({"proposal_id": identifier, "brief_version": integer}), status=201, idempotent=True)
endpoint("/projects/{id}/intake", "post", "changeProjectIntake", reference("VersionedId"), obj({"accepting_proposals": boolean, "version": integer}), idempotent=True)
endpoint("/creators", "get", "listCreators", obj({"data": array(reference("Profile"))}), authenticated=False, query=["q"])
endpoint("/creators/mine", "get", "getOwnProfile", obj({"profile": nullable(reference("Profile"))}))
endpoint("/creators", "post", "saveProfile", reference("Profile"), obj({"profile": obj({
    "headline": string, "bio": string, "rate_minor": integer, "currency": string, "skills": array(string),
})}))
endpoint("/engagements", "get", "listEngagements", obj({"data": array(reference("Engagement"))}))
endpoint("/engagements/{id}", "get", "getEngagement", reference("Engagement"), query=["versions_cursor", "feedback_cursor", "limit"])
endpoint("/engagements/{id}/submit", "post", "submitWork", reference("VersionedId"), obj({"content": string, "title": {"type": "string", "maxLength": 160}, "ready_for_acceptance": boolean, "file_ids": {"type": "array", "maxItems": 8, "uniqueItems": True, "items": identifier}}, ["content"]), status=201, idempotent=True)
endpoint("/engagements/{id}/start", "post", "startWork", reference("Id"), idempotent=True)
endpoint("/engagements/{id}/feedback", "post", "recordWorkFeedback", reference("Id"), obj({"content": {"type": "string", "minLength": 1, "maxLength": 4000}, "submission_id": nullable(identifier), "kind": {"type": "string", "enum": ["comment", "changes_requested"]}}, ["content"]), status=201, idempotent=True)
endpoint("/engagements/{id}/archive", "get", "downloadWorkArchive", None, query=["submission_id"])
paths["/engagements/{id}/archive"]["get"]["parameters"][-1].update(required=True, schema=identifier)
paths["/engagements/{id}/archive"]["get"]["responses"]["200"]["content"] = {"application/zip": {"schema": {"type": "string", "format": "binary"}}}
for method, operation, response, status in [("get", "listWorkFiles", obj({"data": array(reference("WorkFile"))}), 200), ("post", "uploadWorkFile", reference("WorkFile"), 201)]:
    path = "/engagements/{engagement_id}/work_files"
    endpoint(path, method, operation, response, status=status, idempotent=method == "post")
    paths[path][method]["parameters"].append({"name": "engagement_id", "in": "path", "required": True, "schema": identifier})
paths["/engagements/{engagement_id}/work_files"]["post"]["requestBody"] = {"required": True, "content": {"multipart/form-data": {"schema": obj({"file": {"type": "string", "format": "binary"}})}}}
for suffix, method, operation, response, status in [("", "get", "getWorkFile", reference("WorkFile"), 200), ("", "delete", "removeWorkFile", None, 204), ("/download", "get", "downloadWorkFile", None, 200)]:
    path = "/engagements/{engagement_id}/work_files/{id}" + suffix
    endpoint(path, method, operation, response, status=status)
    paths[path][method]["parameters"].append({"name": "engagement_id", "in": "path", "required": True, "schema": identifier})
paths["/engagements/{engagement_id}/work_files/{id}/download"]["get"]["responses"]["200"]["content"] = {"application/octet-stream": {"schema": {"type": "string", "format": "binary"}}}
endpoint("/engagements/{id}/accept", "post", "acceptSubmission", reference("Id"), obj({"submission_id": identifier}), idempotent=True)
endpoint("/engagements/{engagement_id}/finance", "get", "getFinance", reference("Finance"))
endpoint("/engagements/{engagement_id}/finance", "post", "requestPayment", reference("Id"), obj({
    "kind": {"type": "string", "enum": ["fund", "payout"]},
    "scenario": {"type": "string", "enum": ["normal", "timeout_after_success", "decline"]},
}), status=201, idempotent=True)
endpoint("/engagements/{engagement_id}/hold", "post", "placeHold", reference("Id"), obj({"reason": string}), idempotent=True)
endpoint("/notifications", "get", "listNotifications", obj({"data": array(reference("Notification"))}))
endpoint("/notifications/{id}", "patch", "readNotification", None, status=204)
endpoint("/operations", "get", "getOperations", reference("Operations"))
endpoint("/operations/reconcile", "post", "reconcile", obj({"checked": integer, "recovered": integer, "exceptions": integer}))
endpoint("/operations/settlements/{id}/release", "post", "releaseHold", reference("Id"), obj({"reason": string}))
endpoint("/operations/deliveries/{id}/retry", "post", "retryDelivery", reference("Id"))
endpoint("/portfolio", "get", "listPortfolio", obj({"data": array(reference("PortfolioItem"))}))
endpoint("/portfolio", "post", "uploadPortfolio", obj({"id": identifier, "state": string}), status=201)
paths["/portfolio"]["post"]["requestBody"] = {
    "required": True, "content": {"multipart/form-data": {"schema": obj({
        "title": string, "file": {"type": "string", "format": "binary"},
    })}},
}
endpoint("/portfolio/{id}/download", "get", "downloadPortfolio", None)
paths["/portfolio/{id}/download"]["get"]["responses"]["200"]["content"] = {"application/octet-stream": {"schema": {"type": "string", "format": "binary"}}}
endpoint("/webhooks/sandbox", "post", "receiveWebhook", obj({"received": boolean}), obj({"event_id": string, "operation_id": identifier}), authenticated=False)
paths["/webhooks/sandbox"]["post"]["parameters"] = [
    {"name": name, "in": "header", "required": True, "schema": string}
    for name in ["X-Mesh-Timestamp", "X-Mesh-Signature"]
]

publishing = json.loads((Path(__file__).resolve().parents[1] / "contracts" / "publishing.json").read_text(encoding="utf-8"))
schemas.update(publishing["schemas"])
paths.update(publishing["paths"])

contract = {
    "openapi": "3.1.1",
    "info": {"title": "MESH API", "version": "0.1.0", "description": "Creator marketplace. Finance endpoints are an explicitly isolated sandbox. Publishing is an operator-only isolated integration laboratory."},
    "servers": [{"url": "/api/v1"}],
    "paths": paths,
    "components": {
        "securitySchemes": {"sessionCookie": {"type": "apiKey", "in": "cookie", "name": "_mesh_session"}},
        "schemas": schemas,
    },
}
destination = Path(__file__).resolve().parents[1] / "contracts" / "openapi.json"
if "--check" in sys.argv:
    if json.loads(destination.read_text(encoding="utf-8")) != contract:
        raise SystemExit("OpenAPI authoring sources differ from the generated contract.")
    print("OpenAPI authoring sources agree with the generated contract.")
else:
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(json.dumps(contract, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

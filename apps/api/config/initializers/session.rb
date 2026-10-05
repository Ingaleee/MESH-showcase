Rails.application.config.session_store :cookie_store,
  key: ENV.fetch("MESH_SESSION_COOKIE", "_mesh_showcase_session"),
  same_site: :lax,
  secure: Rails.env.production?,
  httponly: true,
  expire_after: 12.hours

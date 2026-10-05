if Rails.env.production?
  require Rails.root.join("lib/api/deployment_configuration")
  Api::DeploymentConfiguration.validate!(ENV)
end

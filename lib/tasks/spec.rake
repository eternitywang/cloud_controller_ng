desc "Runs all specs"
task spec: %w[
              db:recreate
              spec:outer
              spec:unit:fast
              spec:unit:lib
              spec:unit:controllers
            ]

namespace :spec do
  task api: "db:pick" do
    sh "bundle exec rspec spec/api --format RspecApiDocumentation::ApiFormatter"
  end

  task acceptance: "db:pick" do
    run_specs("spec/acceptance")
  end

  task integration: "db:pick" do
    run_specs("spec/integration")
  end

  task outer: %w[api acceptance integration]

  namespace :unit do
    fast_suites = %w[
        access
        jobs
        models
        presenters
        repositories
      ]

    fast_suites.each do |layer_name|
      task layer_name => "db:pick" do
        run_specs("spec/unit/#{layer_name}")
      end
    end

    task fast: fast_suites

    task :lib do
      run_specs("spec/unit/lib")
    end

    task :controllers do
      run_specs("spec/unit/controllers")
    end
  end

  def run_specs(path)
    sh "bundle exec rspec #{path} --require rspec/instafail --format RSpec::Instafail"
  end
end

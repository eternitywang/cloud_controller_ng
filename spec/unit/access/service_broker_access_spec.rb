require 'spec_helper'

module VCAP::CloudController
  describe ServiceBrokerAccess, type: :access do
    subject(:access) { ServiceBrokerAccess.new(Security::AccessContext.new) }
    let(:token) {{ 'scope' => ['cloud_controller.read', 'cloud_controller.write'] }}
    let(:user) { VCAP::CloudController::User.make }
    let(:org) { VCAP::CloudController::Organization.make }
    let(:space) { VCAP::CloudController::Space.make(:organization => org) }
    let(:app) { VCAP::CloudController::AppFactory.make(:space => space) }
    let(:object) { VCAP::CloudController::ServiceBroker.make }

    before do
      SecurityContext.set(user, token)
    end

    after do
      SecurityContext.clear
    end

    it_should_behave_like :admin_full_access

    context 'organization manager (defensive)' do
      before { org.add_manager(user) }
      it_behaves_like :no_access
      it { is_expected.not_to allow_op_on_object :index, VCAP::CloudController::ServiceBroker }
    end

    context 'organization user (defensive)' do
      before { org.add_user(user) }
      it_behaves_like :no_access
      it { is_expected.not_to allow_op_on_object :index, VCAP::CloudController::ServiceBroker }
    end

    context 'user in a different organization (defensive)' do
      before do
        different_organization = VCAP::CloudController::Organization.make
        different_organization.add_user(user)
      end

      it_behaves_like :no_access
      it { is_expected.not_to allow_op_on_object :index, VCAP::CloudController::ServiceBroker }
    end

    context 'manager in a different organization (defensive)' do
      before do
        different_organization = VCAP::CloudController::Organization.make
        different_organization.add_manager(user)
      end

      it_behaves_like :no_access
      it { is_expected.not_to allow_op_on_object :index, VCAP::CloudController::ServiceBroker }
    end

    context 'a user that isnt logged in (defensive)' do
      let(:user) { nil }
      it_behaves_like :no_access
      it { is_expected.not_to allow_op_on_object :index, VCAP::CloudController::ServiceBroker }
    end
  end
end

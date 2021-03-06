require 'spec_helper'
require 'handlers/processes_handler'

module VCAP::CloudController
  describe ProcessUpdateMessage do
    context 'when a name parameter is provided' do
      let(:body) { '{ "name": "my-name" }' }
      let(:guid) { 'my-guid' }

      it 'is not valid' do
        update_message = ProcessUpdateMessage.create_from_http_request(guid, body)
        errors = update_message.validate
        expect(errors).to include('The name field cannot be updated on a Process')
      end
    end

    context 'when nil opts are  provided' do
      let(:body) { nil }
      let(:guid) { 'my-guid' }

      it 'is not valid' do
        update_message = ProcessUpdateMessage.create_from_http_request(guid, body)
        errors = update_message.validate
        expect(errors).to include('Invalid Process')
      end
    end
  end

  describe ProcessesHandler do
    let(:security_context) { double(:sc, current_user: User.new(guid: '123'), current_user_email: 'user@user.com') }
    let(:process_repo) { double(:process_repo) }
    let(:process_event_repo) { double(:process_event_repo) }
    let(:space) { Space.make }
    let!(:handler) { ProcessesHandler.new(process_repo, process_event_repo) }
    let(:process_opts) { {space: space} }
    let!(:process) do
      process_model = AppFactory.make(process_opts)
      ProcessMapper.map_model_to_domain(process_model)
    end

    context '#update' do
      context 'changing type to an invalid value' do
        it 'raises an InvalidProcess exception' do
          update_opts = { 'type' => 'worker' }

          process_model2 = AppFactory.make(space: space, type: 'worker')

          updated_process = process.with_changes(update_opts)
          neighbor_processes = [ ProcessMapper.map_model_to_domain(process_model2) ]

          ac = double(:ac, cannot?: false, user: User.make, user_email: 'jim@jim.com')

          update_message = ProcessUpdateMessage.new(process.guid, update_opts)
          allow(process).to receive(:with_changes).with(update_opts).and_return(updated_process)

          expect(process_repo).to receive(:find_for_update).with(process.guid).and_yield(process, space, neighbor_processes)

          expect {
            handler.update(update_message, ac)
          }.to raise_error(ProcessesHandler::InvalidProcess, "Type 'worker' is already in use")
        end
      end

      it 'updates the process and creates an update audit event' do
        update_opts = { 'name' => 'my-process', 'type' => 'web' }

        updated_process = process.with_changes(update_opts)

        ac = double(:ac, cannot?: false, user: User.make, user_email: 'jim@jim.com')

        update_message = ProcessUpdateMessage.new(process.guid, update_opts)

        allow(process).to receive(:with_changes).and_return(updated_process)
        allow(process_repo).to receive(:find_for_update).and_yield(process, space, [])
        allow(process_repo).to receive(:update!).and_return(updated_process)
        allow(process_event_repo).to receive(:record_app_update)

        handler.update(update_message, ac)

        expect(process).to have_received(:with_changes).with(update_opts)
        expect(process_repo).to have_received(:find_for_update).with(process.guid)
        expect(process_repo).to have_received(:update!).with(updated_process)
        expect(process_event_repo).to have_received(:record_app_update)
          .with(updated_process, space, ac.user, ac.user_email, update_opts)

      end
    end

    context '#create' do
      it 'saves an event when creating a process' do
        creation_opts = { 'space_guid' => space.guid, 'name' => 'my-process' }

        ac = double(:ac, cannot?: false, user: User.make, user_email: 'jim@jim.com')
        process = AppProcess.new(creation_opts)

        create_message = ProcessCreateMessage.new(creation_opts)

        allow(process_repo).to receive(:new_process).and_return(process)
        allow(process_repo).to receive(:create!).and_return(process)
        allow(process_event_repo).to receive(:record_app_create)

        result = handler.create(create_message, ac)

        expect(process_repo).to have_received(:new_process) do |opts|
          expect(opts).to match(hash_including(create_message.opts))
          expect(opts['guid']).to match(/^[a-z0-9\-]+$/)
        end
        expect(process_repo).to have_received(:create!).with(process)
        expect(process_event_repo).to have_received(:record_app_create).
          with(process, space, ac.user, ac.user_email, creation_opts)

        expect(result).to eq(process)
      end
    end

    context '#delete' do
      it 'saves an event when deleting a process' do
        ac = double(:ac, user: User.make, user_email: 'jim@jim.com')

        expect(ac).to receive(:cannot?).with(:delete, process, space).and_return(false)
        allow(process_repo).to receive(:find_for_delete).and_yield(process, space)
        allow(process_repo).to receive(:delete).and_return(process)

        expect(process_event_repo).to receive(:record_app_delete_request)
          .with(process, space, ac.user, ac.user_email, true)

        expect(handler.delete(process.guid, ac)).to eq(process)
      end
    end
  end
end

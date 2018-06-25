require_relative '../../../spec_helpers/acceptance_spec_helper'

resource 'Services (prefix: /services)' do
  header 'Accept', 'application/json'
  header 'Content-Type', 'application/json'

  let(:someid) { '1001' }
  let(:otherid) { '2001' }
  let(:invalid_id) { '2002' }
  let(:provider_key) { 'foo' }
  let(:state) { :active }

  before do
    ThreeScale::Backend::Service.save!(provider_key: provider_key, id: someid)
    ThreeScale::Backend::Service.save!(provider_key: provider_key, id: otherid, state: state)
  end

  get '/services/:id' do
    parameter :id, 'Service ID', required: true

    let(:id) { someid }

    example_request 'Get Service by ID' do
      expect(response_json['service']['id']).to eq id
      expect(response_json['service']['provider_key']).to eq provider_key
      expect(status).to eq 200
    end

    example 'Try to get a Service by non-existent ID' do
      do_request(id: invalid_id)
      expect(status).to eq 404
      expect(response_json['error']).to match /not_found/
    end

    describe 'Get service and check state' do
      context 'when state is not set' do
        let(:id) { someid }
        example_request 'Get Service by ID' do
          expect(status).to eq 200
          expect(response_json['service']['id']).to eq id
          expect(response_json['service']['state']).to eq 'active'
        end
      end
      context 'when state is active' do
        let(:id) { otherid }
        example_request 'Get Service by ID' do
          expect(status).to eq 200
          expect(response_json['service']['id']).to eq id
          expect(response_json['service']['state']).to eq 'active'
        end
      end
      context 'when state is set to nil' do
        let(:id) { otherid }
        let(:state) { nil }
        example_request 'Get Service by ID' do
          expect(status).to eq 200
          expect(response_json['service']['id']).to eq id
          expect(response_json['service']['state']).to eq 'active'
        end
      end
      context 'when state is suspended' do
        let(:state) { :suspended }
        let(:id) { otherid }
        example_request 'Get Service by ID' do
          expect(status).to eq 200
          expect(response_json['service']['id']).to eq id
          expect(response_json['service']['state']).to eq state.to_s
        end
      end
      context 'with an service that has invalid state in db' do
        let(:id) { otherid }
        let(:storage) { ThreeScale::Backend::Storage.instance }
        example 'Get Service by ID should return inactive state' do
          storage.set ThreeScale::Backend::Service.storage_key(id, 'state'), 'invalid_state'
          do_request(id: id)
          expect(status).to eq 200
          expect(response_json['service']['id']).to eq id
          expect(response_json['service']['state']).to eq 'suspended'
        end
      end
      context 'with an service that has no state in db' do
        let(:id) { otherid }
        let(:storage) { ThreeScale::Backend::Storage.instance }
        example 'Get Service by ID should return inactive state' do
          storage.del ThreeScale::Backend::Service.storage_key(id, 'state')
          do_request(id: id)
          expect(status).to eq 200
          expect(response_json['service']['id']).to eq id
          expect(response_json['service']['state']).to eq 'active'
        end
      end
    end
  end

  post '/services/' do
    parameter :service, 'Service attributes', required: true

    let(:state) { :active }
    let(:service) do
      {
        id: '1002',
        provider_key: 'foo',
        referrer_filters_required: true,
        backend_version: 'oauth',
        default_user_plan_name: 'default user plan name',
        default_user_plan_id: 'plan ID',
        default_service: true,
        state: state
      }
    end
    let(:raw_post){ params.to_json }

    example_request 'Create a Service' do
      expect(status).to eq 201
      expect(response_json['status']).to eq 'created'

      svc = ThreeScale::Backend::Service.load_by_id('1002')
      expect(svc.to_hash).to eq service.merge(user_registration_required: true)
    end

    example 'Try creating a Service with invalid data' do
      do_request(service: { user_registration_required: false,
                            default_user_plan_name: nil,
                            default_user_plan_id: nil })

      expect(status).to eq 400
      expect(response_json['error']).to match /require a default user plan/
    end

    example 'Try creating a Service without specifying the service parameter in the body' do
      do_request(service: nil)

      expect(status).to eq 400
      expect(response_json['error']).to match /missing parameter 'service'/
    end

    example 'Create a Service with extra params that should be ignored' do
      do_request service: service.merge(some_param: 'some_value')
      expect(status).to eq 201
      expect(response_json['status']).to eq 'created'

      svc = ThreeScale::Backend::Service.load_by_id('1002')
      expect(svc).not_to be_nil
      expect(svc).not_to respond_to :some_param
      # The returned data should not contain *some_param* attribute
      expect(svc.to_hash).to eq service.merge(user_registration_required: true)
    end

    context 'with an service that has no state' do
      let(:state) { nil }

      example_request 'creating the service returns an active service' do
        expect(status).to eq 201
        expect(response_json['status']).to eq 'created'

        svc = ThreeScale::Backend::Service.load_by_id('1002')
        expect(svc).not_to be_nil
        expect(svc.active?).to be_truthy
      end
    end

    context 'Create a Service with invalid state' do
      let(:state) { :invalid_state }

      example_request 'returns inactive service' do
        expect(status).to eq 201
        svc = ThreeScale::Backend::Service.load_by_id('1002')
        expect(svc).not_to be_nil
        expect(svc.active?).to be_falsy
      end
    end
  end

  put '/services/:id' do
    parameter :id, 'Service ID', required: true
    parameter :service, 'Service attributes', required: true

    let(:id){ 1001 }
    let(:state) { :active }
    let(:service) do
      {
        provider_key: 'foo',
        referrer_filters_required: true,
        backend_version: 'oauth',
        default_user_plan_name: 'default user plan name',
        default_user_plan_id: 'plan ID',
        default_service: true,
        state: state
      }
    end
    let(:raw_post){ params.to_json }

    example_request 'Update Service by ID' do
      expect(status).to eq 200
      expect(response_json['status']).to eq 'ok'

      svc = ThreeScale::Backend::Service.load_by_id('1001')
      expect(svc.to_hash).to eq service.merge(id: '1001',
                                              user_registration_required: true)
    end

    example 'Update Service by ID using extra params that should be ignored' do
      do_request service: service.merge(some_param: 'some_value')
      expect(status).to eq 200
      expect(response_json['status']).to eq 'ok'

      svc = ThreeScale::Backend::Service.load_by_id('1001')
      expect(svc).not_to be_nil
      expect(svc).not_to respond_to :some_param
      # The returned data should not contain *some_param* attribute
      expect(svc.to_hash).to eq service.merge(id: '1001',
                                              user_registration_required: true)
    end

    example 'Try updating Service with invalid data' do
      do_request(service: { user_registration_required: false,
                            default_user_plan_name: nil,
                            default_user_plan_id: nil })

      expect(status).to eq 400
      expect(response_json['error']).to match /require a default user plan/
    end

    context 'Create a service that has no state' do
      let(:state) { nil }

      example_request 'creating the service returns an active service' do
        expect(status).to eq 200
        expect(response_json['status']).to eq 'ok'

        svc = ThreeScale::Backend::Service.load_by_id('1001')
        expect(svc.active?).to be_truthy
      end
    end

    context 'Create a Service with invalid state' do
      let(:state) { :invalid_state }

      example_request 'returns inactive service' do
        expect(status).to eq 200
        svc = ThreeScale::Backend::Service.load_by_id('1001')
        expect(svc).not_to be_nil
        expect(svc.active?).to be_falsy
      end
    end
  end

  put '/services/change_provider_key/:key' do
    parameter :key, 'Existing provider key', required: true
    parameter :new_key, 'New provider key', required: true

    let(:key){ 'foo' }
    let(:new_key){ 'bar' }
    let(:raw_post) { params.to_json }

    example_request 'Changing a provider key'do
      expect(status).to eq 200
      expect(response_json['status']).to eq 'ok'
    end

    example_request 'Trying to change a provider key to empty', new_key: '' do
      expect(status).to eq 400
      expect(response_json['error']).to match /keys are not valid/
    end

    example 'Trying to change a provider key to an existing one' do
      ThreeScale::Backend::Service.save! id: 7002, provider_key: 'bar'
      do_request new_key: 'bar'

      expect(status).to eq 400
      expect(response_json['error']).to match /already exists/
    end

    example_request 'Trying to change a non-existent provider key', key: 'baz' do
      expect(status).to eq 400
      expect(response_json['error']).to match /does not exist/
    end
  end

  delete '/services/:id' do
    parameter :id, 'Service ID', required: true

    let(:raw_post) { params.to_json }

    example_request 'Deleting a default service', id: 1001 do
      expect(status).to eq 400
      expect(response_json['error']).to match /cannot be removed/
    end

    example 'Deleting a non-default service' do
      ThreeScale::Backend::Service.save!(provider_key: 'foo', id: 1002)
      do_request id: 1002

      expect(status).to eq 200
      expect(response_json['status']).to eq 'deleted'
    end
  end
end

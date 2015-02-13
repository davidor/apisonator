require '3scale/backend/transactor/notify_batcher'
require '3scale/backend/transactor/notify_job'
require '3scale/backend/transactor/process_job'
require '3scale/backend/transactor/report_job'
require '3scale/backend/transactor/log_request_job'
require '3scale/backend/transactor/status'
require '3scale/backend/cache'
require '3scale/backend/errors'
require '3scale/backend/validators'
require '3scale/backend/aggregator/stats_keys'

module ThreeScale
  module Backend
    # Methods for reporting and authorizing transactions.
    module Transactor
      include Backend::StorageKeyHelpers
      include Backend::Cache
      include NotifyBatcher
      extend self

      def report(provider_key, service_id, transactions)
        service = load_service!(provider_key, service_id)

        report_enqueue(service.id, transactions)
        notify(
          provider_key,
          'transactions/create_multiple' => 1,
          'transactions' => transactions.size)
      end

      def authorize(provider_key, params, options = {})
        do_authorize :authorize, provider_key, params, options
      end

      def oauth_authorize(provider_key, params, options = {})
        do_authorize :oauth_authorize, provider_key, params, options
      end

      def authrep(provider_key, params, options = {})
        do_authrep :authrep, provider_key, params, options
      end

      def oauth_authrep(provider_key, params, options = {})
        do_authrep :oauth_authrep, provider_key, params, options
      end

      def utilization(service_id, application_id)
        #service = Service.load_by_id!(service_id)
        #raise ProviderKeyInvalid, provider_key if service.nil? || service.provider_key!=provider_key

        application = Application.load!(service_id, application_id)
        usage = load_current_usage(application)
        status = ThreeScale::Backend::Transactor::Status.new(:application => application, :values => usage)
        ThreeScale::Backend::Validators::Limits.apply(status, {})

        max_utilization = 0
        max_record = 0

        max_utilization, max_record = ThreeScale::Backend::Alerts.utilization(status) if status.usage_reports.size > 0
        max_utilization = (max_utilization * 100.to_f).round

        stats = ThreeScale::Backend::Alerts.stats(service_id, application_id)

        return [status.usage_reports, max_record, max_utilization, stats]

      end

      def alert_limit(service_id)
        #service = Service.load_by_id!(service_id)
        #raise ProviderKeyInvalid, provider_key if service.nil? || service.provider_key!=provider_key
        @list = Alerts.list_allowed_limit(service_id)
      end

      def add_alert_limit(service_id, limit)
        ##service = Service.load_by_id!(service_id)
        ##raise ProviderKeyInvalid, provider_key if service.nil? || service.provider_key!=provider_key
        @list = Alerts.add_allowed_limit(service_id,limit)
      end

      def delete_alert_limit(service_id, limit)
        #service = Service.load_by_id!(service_id)
        #raise ProviderKeyInvalid, provider_key if service.nil? || service.provider_key!=provider_key
        @list = Alerts.delete_allowed_limit(service_id,limit)
      end


      def latest_events
        EventStorage.list
      end

      def delete_event_by_id(id)
        EventStorage.delete(id)
      end

      def delete_events_by_range(to_id)
        EventStorage.delete_range(to_id)
      end

      ## -------------------

      private

      COMMON_VALIDATORS = [
                    Validators::Referrer,
                    Validators::State,
                    Validators::Limits
      ]

      VALIDATORS = [Validators::Key] + COMMON_VALIDATORS

      OAUTH_VALIDATORS = [Validators::OauthSetting,
                          Validators::OauthKey,
                          Validators::RedirectUrl] + COMMON_VALIDATORS

      def authorize_nocache(method, provider_key, params, options = {})
        oauth = method == :oauth_authorize
        user_key = oauth ? nil : params[:user_key]
        do_validators(oauth, provider_key, params[:service_id], params[:app_id], params[:user_id], user_key, nil, params)
      end

      ## this is the classic way to do an authrep in case the cache fails, there
      ## has been changes on the underlying data or the time to life has elapsed
      def authrep_nocache(method, provider_key, params, options = {})
        oauth = method == :oauth_authrep
        user_key = oauth ? nil : params[:user_key]
        do_validators(oauth, provider_key, params[:service_id], params[:app_id], params[:user_id], user_key, params[:usage], params)
      rescue ThreeScale::Backend::ApplicationNotFound, ThreeScale::Backend::UserNotDefined => e
        # we still want to track these
        notify(provider_key, 'transactions/authorize' => 1)
        raise e
      end

      def do_validators(oauth, provider_key, service_id, app_id, user_id, user_key, usage, params)
        service = load_service!(provider_key, service_id)

        if oauth
          # if app_id (client_id) isn't defined, check for access_token and
          # resolve it to the app_id
          if app_id.nil? or app_id.empty?
            access_token = params[:access_token]
            raise ApplicationNotFound.new(app_id) if access_token.nil? or access_token.empty?
            app_id = OAuthAccessTokenStorage.get_app_id(service.id, access_token)
            raise AccessTokenInvalid.new(access_token) if app_id.nil? || app_id.empty?
          end
          validators = OAUTH_VALIDATORS
        else
          validators = VALIDATORS
        end

        application = Application.load_by_id_or_user_key!(service.id,
                                                          app_id,
                                                          user_key)

        user         = load_user!(application, service, user_id)
        usage_values = load_current_usage(application)
        user_usage   = load_user_current_usage(user) if user
        status_attrs = {
          user_values: user_usage,
          application: application,
          service:     service,
          oauth:       oauth,
          usage:       usage,
          values:      usage_values,
          user:        user,
        }

        status = apply_validators(validators, status_attrs, params)

        [status, service, application, user]
      end

      def do_authorize(method, provider_key, params, options)
        notify(provider_key, 'transactions/authorize' => 1)
        ## FIXME: oauth is never called, the ttl of the access_token makes the ttl of the cached results change
        sanitize_and_cache_auth(method, provider_key, params[:usage], method == :oauth_authorize || params[:no_caching], params, options) do |opts|
          authorize_nocache(method, provider_key, params, opts)
        end
      end

      def do_authrep(method, provider_key, params, options)
        usage = params[:usage]
        ret = sanitize_and_cache_auth(method, provider_key, usage, params[:no_caching], params, options) do |opts|
          authrep_nocache(method, provider_key, params, opts)
        end

        status, _, status_result, service, application, user, service_id = ret

        if application.nil?
          application_id = params[:app_id]
          application_id = params[:user_key] if params[:app_id].nil?
          username = params[:user_id]
        else
          service_id = service.id
          application_id = application.id
          username = nil
          username = user.username unless user.nil?
        end

        if (usage || params[:log]) && ((status && status.authorized?) || (status.nil? && status_result))
          report_enqueue(service_id, ({ 0 => {"app_id" => application_id, "usage" => usage, "user_id" => username, "log" => params[:log]}}))
          val = usage ? usage.size : 0
          ## FIXME: we need to account for the log_request to, so far we are not counting them, to be defined a metric
          notify(provider_key, 'transactions/authorize' => 1, 'transactions/create_multiple' => 1, 'transactions' => val)
        else
          notify(provider_key, 'transactions/authorize' => 1)
        end

        ret
      end

      def sanitize_and_cache_auth(method, provider_key, usage, no_cache, params, options)
        check_values_of_usage(usage) unless usage.nil?

        status = nil
        status_xml = nil
        status_result = nil
        data_combination = nil
        cache_miss = true

        unless no_cache
          ## check if the keys/id combination has been seen before
          isknown, service_id, data_combination, dirty_app_xml, dirty_user_xml, caching_allowed = combination_seen(method, provider_key, params)

          if caching_allowed && isknown && !service_id.nil? && !dirty_app_xml.nil?
            unless usage.nil?
              options[:usage] = usage
              options[:add_usage_on_report] = true if method == :authrep || method == :oauth_authrep
            end
            status_xml, status_result, violation = clean_cached_xml(dirty_app_xml, dirty_user_xml, options)
            cache_miss = false unless status_xml.nil? || status_result.nil? || violation
          end
        end

        if cache_miss
          report_cache_miss
          status, service, application, user = yield(options)
          combination_save(data_combination) unless data_combination.nil? || !caching_allowed
          status_xml = nil
          status_result = nil
        else
          report_cache_hit
        end

        [status, status_xml, status_result, service, application, user, service_id]
      end

      def load_user!(application, service, user_id)
        user = nil

        if not (user_id.nil? || user_id.empty? || !user_id.is_a?(String))
          ## user_id on the paramters
          if application.user_required?
            user = User.load_or_create!(service, user_id)
            raise UserRequiresRegistration, service.id, user_id unless user
          else
            user_id = nil
          end
        else
          raise UserNotDefined, application.id if application.user_required?
          user_id = nil
        end

        user
      end

      def load_service!(provider_key, id)
        id = Service.default_id!(provider_key) if id.nil? || id.empty?
        service = Service.load_by_id(id.split('-').last) || Service.load_by_id!(id)

        raise ProviderKeyInvalid, provider_key if service.provider_key != provider_key

        service
      end

      def apply_validators(validators, status_attrs, params)
        Status.new(status_attrs).tap do |st|
          validators.all? do |validator|
            if validator == Validators::Referrer && !st.service.referrer_filters_required?
              true
            elsif validator == Validators::Key && st.service.backend_version.to_i == 1
              true
            else
              validator.apply(st, params)
            end
          end
        end
      end

      ## this is required because values are checked only on creation of the status
      ## object and this does not happen on cache, no need to do the same for the metrics
      ## because those are covered by the signature

      def check_values_of_usage(usage)
        usage.each do |metric, value|
          raise UsageValueInvalid.new(metric, value) unless sane_value?(value)
        end
      end

      ## duplicated in metric/collection.rb
      def sane_value?(value)
        value.is_a?(Numeric) || value.to_s =~ /\A\s*#?\d+\s*\Z/
      end

      ##
      # TODO: Check who is calling this method.
      ##
      def run_validators(validators_set, service, application, user, params)
        status = Status.new(:service => service, :application => application).tap do |st|
          validators_set.all? do |validator|
            if validator == Validators::Referrer && !st.service.referrer_filters_required?
              true
            else
              validator.apply(st, params)
            end
          end
        end
        return status
      end

      def check_for_users(service, application, params)
        if application.user_required?
          raise UserNotDefined, application.id if params[:user_id].nil? || params[:user_id].empty? || !params[:user_id].is_a?(String)

          if service.user_registration_required?
            raise UserRequiresRegistration, service.id, params[:user_id] unless service.user_exists?(params[:user_id])
          end
        else
          ## for sanity, it's important to get rid of the request parameter :user_id if the
          ## plan is default. :user_id is passed all the way up and sometimes its existance
          ## is the only way to know which application plan we are in (:default or :user)
          params[:user_id] = nil
        end
        return params
      end

      def report_enqueue(service_id, data)
        Resque.enqueue(ReportJob, service_id, data, Time.now.getutc.to_f)
      end

      def notify(provider_key, usage)
        ## No longer create a job, but for efficiency the notify jobs (incr stats for the master) are
        ## batched. It used to be like this:
        ## tt = Time.now.getutc
        ## Resque.enqueue(NotifyJob, provider_key, usage, encode_time(tt), tt.to_f)
        ##
        ## Basically, instead of creating a NotifyJob directly, which would trigger between 10-20 incrby
        ## we store the data of the job in redis on a list. Once there are configuration.notification_batch
        ## on the list, the worker will fetch the list, aggregate them in a single NotifyJob will all the
        ## sums done in memory and schedule the job as a NotifyJob. The advantage is that instead of having
        ## 20 jobs doing 10 incrby of +1, you will have a single job doing 10 incrby of +20
        notify_batch(provider_key, usage)
      end

      def encode_time(time)
        time.to_s
      end

      ## copied from transactor.rb
      def load_user_current_usage(user)
        pairs = Array.new
        metric_ids = Array.new
        user.usage_limits.each do |usage_limit|
          pairs << [usage_limit.metric_id, usage_limit.period]
          metric_ids << usage_limit.metric_id
        end

        return {} if pairs.nil? or pairs.size==0

        # preloading metric names
        user.metric_names = Metric.load_all_names(user.service_id, metric_ids)
        now = Time.now.getutc
        keys = pairs.map do |metric_id, period|
          Aggregator::StatsKeys.user_usage_value_key(user, metric_id, period, now)
        end
        raw_values = storage.mget(*keys)
        values     = {}
        pairs.each_with_index do |(metric_id, period), index|
          values[period] ||= {}
          values[period][metric_id] = raw_values[index].to_i
        end
        values
      end

      def load_current_usage(application)
        pairs = Array.new
        metric_ids = Array.new
        application.usage_limits.each do |usage_limit|
          pairs << [usage_limit.metric_id, usage_limit.period]
          metric_ids << usage_limit.metric_id
        end
        ## Warning this makes the test transactor_test.rb fail, weird because it didn't happen before
        return {} if pairs.nil? or pairs.size==0

        # preloading metric names
        application.metric_names = Metric.load_all_names(application.service_id, metric_ids)
        now = Time.now.getutc
        keys = pairs.map do |metric_id, period|
          Aggregator::StatsKeys.usage_value_key(application, metric_id, period, now)
        end
        raw_values = storage.mget(*keys)
        values     = {}
        pairs.each_with_index do |(metric_id, period), index|
          values[period] ||= {}
          values[period][metric_id] = raw_values[index].to_i
        end
        values
      end

      def storage
        Storage.instance
      end
    end
  end
end

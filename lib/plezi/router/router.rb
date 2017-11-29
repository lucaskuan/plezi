require 'plezi/router/route'
require 'plezi/router/errors'
require 'plezi/router/assets'
require 'plezi/router/adclient'

module Plezi
   module Base
      # this module is incharge of routing requests to the correct Controller.
      module Router
         @routes = []
         @app = nil

         module_function

         # Creates a new router
         def new(app)
            if app && app != call_method
               puts 'Plezi as Middleware'
               @app = app
            end
            Plezi.app
         end

         # called when an HTTP request had arrived
         def call(env)
            puts 'Incoming HTTP request'
            puts env.inspect
            request = Rack::Request.new(env)
            response = Rack::Response.new
            ret = nil
            @routes.each { |route| ret = route.call(request, response); break if ret }
            unless ret
               return @app.call(env) if @app
               ret = ::Plezi::Base::Err404Ctrl.new._pl_respond(request, response, request.params)
            end
            response.write(ret) if ret.is_a?(String)
            return response.finish
         rescue => e
            puts e.message, e.backtrace
            response = Rack::Response.new
            response.write ::Plezi::Base::Err500Ctrl.new._pl_respond(request, response, request.params)
            return response.finish
         end

         # returns the `call` method. Used repeatedly in middleware mode and only once in application mode.
         def call_method
            @call_method ||= Plezi::Base::Router.method(:call)
         end

         # Creates a new route.
         #
         # `path`:: should be a string describing the route. Named parameters are allowed.
         # `controller`:: should be a Class object that will receive all the class properties of a Plezi Controller, or one of the allowed keywords.
         def route(path, controller)
            path = path.chomp('/'.freeze) unless path == '/'.freeze
            case controller
            when :client
               controller = ::Plezi::Base::Router::ADClient
            when :assets
               controller = ::Plezi::Base::Assets
               path << '/*'.freeze unless path[-1] == '*'.freeze
            when Regexp
               path << '/*'.freeze unless path[-1] == '*'.freeze
               return @routes << RouteRewrite.new(path, controller)
            end
            @routes << Route.new(path, controller)
         end

         def list
            @routes
         end

         # Returns the URL for requested controller method and paramerets.
         def url_for(controller, method_sym, params = {})
            # GET,PUT,POST,DELETE
            r = nil
            url = '/'.dup
            @routes.each do |tmp|
               case tmp.controller
               when Class
                  next if tmp.controller != controller
                  r = tmp
                  break
               when Regexp
                  nm = nil
                  nm = tmp.param_names[0] if params[tmp.param_names[0]]
                  nm ||= tmp.param_names[0].to_sym
                  url << "#{params.delete nm}/" if params[nm] && params[nm].to_s =~ tmp.controller
               else
                  next
               end
            end
            return nil if r.nil?
            case method_sym.to_sym
            when :new
               params.delete :id
               params.delete :_method
               params.delete '_method'.freeze
               params['id'.freeze] = :new
            when :create
               params['id'.freeze] = :new
               params.delete :id
               params['_method'.freeze] = :post
               params.delete :_method
            when :update
               params.delete :_method
               params['_method'.freeze] = :put
            when :delete
               params.delete :_method
               params['_method'.freeze] = :delete
            when :index
               params.delete 'id'.freeze
               params.delete '_method'.freeze
               params.delete :id
               params.delete :_method
            when :show
               raise "The URL for ':show' MUST contain a valid 'id' parameter for the object's index to display." unless params['id'.freeze].nil? && params[:id].nil?
               params.delete '_method'.freeze
               params.delete :_method
            else
               params.delete :id
               params['id'.freeze] = method_sym
            end
            names = r.param_names
            url.chomp! '/'.freeze
            url << r.prefix
            url.clear if url == '/'.freeze
            while names.any? && params[name[0]]
               url << "/#{Rack::Utils.escape params[names.shift]}"
            end
            url << '/'.freeze if url.empty?
            (url << '?') << Rack::Utils.build_nested_query(params) if params.any?
            url
         end
      end
   end
end

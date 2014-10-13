module Anorexic

	module AnoRack

		# the router - this is the actuale application object for the RackServer
		class Router
			attr_accessor :routes
			def initialize
				@routes = []
			end
			def call env
				path_requested = env["PATH_INFO"].to_s.chomp '/'
				# set response object
				response = Rack::Response.new
				# set request object
				request = Rack::Request.new(env)
				# allow lookup of params as keys run:
				self.class.make_hash_accept_symbols hash: request.params
				self.class.make_hash_accept_symbols hash: request.cookies
				# set magic cookies
				class << request.cookies
					def set_controller controller
						@controller = controller
					end
					def []= key, val
						if @controller
							if val
								@controller.response.set_cookie key, val
							else
								@controller.response.delete_cookie key
							end
						end
						super
					end
				end

				return_value = false
				# compare routes
				@routes.each do |route|
					next unless self.class.match path_requested, route[0], request.params
					if route[1].is_a? Class
						break if return_value = route[1].new(env, request, response)._route_path_to_methods_and_set_the_response_
					elsif route[1].public_methods.include? :call
						if return_value = route[1].call(request, response)
							return_value = response.finish
							break 
						end
					end
				end
				return_value
			end
			def add_route path = "", controller = nil, &block
				unless (controller && (controller.is_a?( Class ) || controller.is_a?( Proc ) ) ) || block
					raise "Counldn't add an empty route! Routes must have either a Controller class or a block statement!"
				end
				if controller.is_a?(Class)
					# add controller magic
					controller = self.class.make_magic controller
				end
				@routes << [path.chomp('/'), block || controller]
			end

			def self.match path_requested, path, params
				if path.is_a? Regexp
					return !(!(path.match path_requested))
				end
				return true if path == '*'
				return true if path == path_requested
				# should this piece of magic stay?
				path, path_requested = path.split('/'), path_requested.split('/')
				path.unshift "" if path.empty?
				if path_requested[0..-2] == path
					params["id"] = path_requested[-1]
					return true
				end
				return false
			end

			# tweeks the params hash to accept :symbols in addition to strings (similar to Rails, but probably different, as two keys, such as "id" and :id can co-exist if the developer isn't careful).
			def self.make_hash_accept_symbols hash
				df_proc = Proc.new do |hs,k|
					if k.is_a?(Symbol) && hs.has_key?( k.to_s)
						hs[k.to_s]
					elsif k.is_a?(String) && hs.has_key?( k.to_sym)
						hs[k.to_sym]
					end
				end
				hash.values.each do |v|
					if v.is_a?(Hash)
						v.default_proc = df_proc
						make_hash_accept_symbols v
					end
				end
			end

			# injects the magic to the controller
			#
			# adds the `redirect_to` and `send_data` methods to the controller class, as well as the properties:
			# env:: the env recieved by the Rack server.
			# params:: the request's paramaters.
			# cookies:: the request's cookies.
			# flash:: an amazing Hash object that sets temporary cookies for one request only - greate for saving data between redirect calls.
			#
			def self.make_magic(controller)
				new_class_name = "AnorexicMegicRuntimeController_#{controller.name.gsub /[\:\-]/, '_'}"
				return Module.const_get new_class_name if Module.const_defined? new_class_name
				ret = Class.new(controller) do
					include Anorexic::ControllerMagic

					def initialize env, request, response
						@env, @request, @params = env, request, request.params
						@response = response
						@response["Content-Type"] = ::Anorexic.default_content_type

						# create magical cookies
						@cookies = request.cookies
						@cookies.set_controller self

						# propegate flash object
						@flash = Hash.new do |hs,k|
							hs["anorexic_flash_#{k}"] if hs.has_key? "anorexic_flash_#{k}"
						end
						cookies.each do |k,v|
							@flash[k] = v if k.start_with? "anorexic_flash_"
						end
						super *[]
					end

					def after
						# remove old flash
						if defined?(super)
							ret = super
							return false if ret == false
						end
						ret ||= true

						cookies.keys.each do |k|
							if k.to_s.start_with? "anorexic_flash_"
								response.delete_cookie k
								flash.delete k
							end
						end
						#set new flash cookies
						@flash.each do |k,v|
							response.set_cookie "anorexic_flash_#{k.to_s}", v
						end
						ret
					end

					def _route_path_to_methods_and_set_the_response_
						available_methods = self.methods
						available_public_methods = (self.class.superclass.public_instance_methods - Object.public_instance_methods) - [:before, :after, :save, :show, :update, :delete, :initialize]
						return false if available_methods.include?(:before) && before == false
						got_from_action = false
						if params && params["id"]
							if (request.delete? || params["_method"].to_s.upcase == 'DELETE') && available_methods.include?(:delete) && !available_public_methods.include?(params["id"].to_sym)
								got_from_action = delete
							elsif request.get?
								if params["id"].to_s[0] != "_" && available_public_methods.include?(params["id"].to_sym)
									got_from_action = self.send params["id"].to_sym
								elsif available_methods.include?(:show)
									got_from_action = show
								end
							elsif (request.put? || request.post? ) && available_methods.include?(:update)
								got_from_action = update
							end
						else
							if request.get? && available_methods.include?(:index)
								got_from_action = index
							elsif (request.put? || request.post?) && available_methods.include?(:save)
								got_from_action = save
							end
						end
						unless got_from_action
							return false
						end
						return false if (available_methods.include?(:after) && after == false)
						response.write got_from_action if got_from_action != true
						response.finish
					end
				end
				Object.const_set(new_class_name, ret)
				ret
			end
		end
	end

end

class ProvidersController < ApplicationController
  rescue_from OpenIDConnect::Discovery::DiscoveryFailed, OpenIDConnect::Discovery::InvalidIdentifier do |e|
    flash[:error] = {
      title: 'Discovery Failed',
      text: 'Could not discover your OP.'
    }
    redirect_to root_url
  end

  def create
    #: scope_{scope_name}=true if user selected scopes
    scopes = params.select{ |k,v| 
                k.index('scope_')==0 }.map{|k,v| 
                    k.sub('scope_','')}

    response_type = params[:implicit]  == "true" ? "id_token token" : "code"

    provider = Provider.discover! params[:host]
    unless provider.registered?
      provider.register! provider_open_id_url(provider)
    end
    redirect_to provider.authorization_uri(
      provider_open_id_url(provider),
      new_nonce,
      response_type,
      scopes
    )
  end
end

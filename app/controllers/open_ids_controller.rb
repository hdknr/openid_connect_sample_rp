class OpenIdsController < ApplicationController
  before_filter :require_anonymous_access

  def show
    begin
      provider = Provider.find params[:provider_id]
      authenticate provider.authenticate(
        provider_open_id_url(provider),
        params[:code],
        stored_nonce
      )
      redirect_to account_url
    rescue =>ex
      #: could be implicit response 
      #: Assertion would be processed by Javascript
      #: in app/views/open_ids/show.html.erb
    end
  end

  def verify
    #: Experimental implementation for Implict Flow
    #: Javascript in the landing HTML  forwords ID Token and Status via POST.
    #:
    #: Landing HTML publish by "show" action in this controller
    #: in the case "code" is not found in the query parameter.
    provider = Provider.find params[:provider_id]
    begin
      acnt= provider.authenticate_by_id_token( params[:id_token],params[:state] ) 
      render json:  {:iss =>  acnt.open_id.identifier, :sub => provider.issuer }
    rescue =>ex
      render json:  {:iss => ex.to_s , :sub => 'no boday' }
    end
  end

  def create
    provider = Provider.find params[:provider_id]
    redirect_to provider.authorization_uri(
      provider_open_id_url(provider),
      new_nonce
    )
  end
end

class MetricsController < ApplicationController
  def create
    validate_metric_params!
    current_threshold = get_current_threshold
    check_cpu_usage_against_current_threshold! current_threshold
    deliver_metrics_to_browser!
    return head(200)
  end

  protected
  def get_current_threshold
    $redis.get("cpu_threshold").to_i || 100
  end
  def check_cpu_usage_against_current_threshold! threshold
    instance_id, cpu_usage = metric_params[:ec2_instance_id], metric_params[:cpu_usage].to_i
    if cpu_usage > threshold and instance_id != 'localhost'
      shutdown_ec2_instance  instance_id
    end
  end
  def shutdown_ec2_instance instance_id
    ShutdownJob.perform_later(instance_id)
    cache_stopped_instances instance_id
  end
  def deliver_metrics_to_browser!
    MetricsBroadcastJob.perform_later metric_params.to_json
  end
  def cache_stopped_instances(instance_id)
    current_stopped_instances = JSON.parse($redis.get("stopped_instances"))
    current_stopped_instances << instance_id
    $redis.set("stopped_instances", current_stopped_instances.to_json)
  end
  def metric_params
    params[:metric]
    #params.require(:metric).permit(:cpu_usage, :disk_usage, :ec2_instance_id, :auth_token, :running_processes => [])
  end
  def auth_token
    Rails.application.secrets.auth_token
  end
  def validate_metric_params!
    raise NotAuthorizedError if metric_params[:auth_token] != auth_token
    raise ActionController::ParameterMissing, "Bad Request" if !metric_params[:cpu_usage].present? or !metric_params[:disk_usage].present? or !metric_params[:running_processes].present? or !metric_params[:ec2_instance_id].present?
  end
end
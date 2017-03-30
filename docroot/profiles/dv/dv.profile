<?php

/**
 * @file
 * Enables modules and site configuration for a dv site installation.
 */

use Drupal\user\Entity\User;

/**
 * Implements hook_install_tasks().
 */
function dv_install_tasks(&$install_state) {

  $tasks = array(
    'dv_install_profile_modules' => array(
      'display_name' => t('Install DV modules'),
      'type' => 'batch',
    ),

    'dv_final_site_setup' => array(
      'display_name' => t('Apply configuration'),
      'type' => 'batch',
      'display' => TRUE,
    ),
  );
  return $tasks;
}

/**
 * Implements hook_install_tasks_alter().
 *
 * Unfortunately we have to alter the verify requirements.
 * This is because of https://www.drupal.org/node/1253774. The dependencies of
 * dependencies are not tested. So adding requirements to our install profile
 * hook_requirements will not work :(. Also take a look at install.inc function
 * drupal_check_profile() it just checks for all the dependencies of our
 * install profile from the info file. And no actually hook_requirements in
 * there.
 */
function dv_install_tasks_alter(&$tasks, $install_state) {
  // Override the core finished task function.
  $tasks['install_finished']['function'] = 'dv_install_finished';
}

/**
 * Installs required modules via a batch process.
 *
 * @param $install_state
 *   An array of information about the current installation state.
 *
 * @return
 *   The batch definition.
 */
function dv_install_profile_modules(&$install_state) {
  $files = system_rebuild_module_data();

  $modules = array(
    'dmt_core' => 'dmt_core',
    'dv_geo_area' => 'dv_geo_area',
    'dv_geo_area_group' => 'dv_geo_area_group',
    'dv_blog' => 'dv_blog',
    'geo_area_group' => 'geo_area_group',
    'dv_user' => 'dv_user',
    'dvm_user_groups' => 'dvm_user_groups',
    'dv_organisation' => 'dv_organisation',
    'dmt_organisation_group' => 'dmt_organisation_group',
    'dv_issue' => 'dv_issue',
    'dv_person' => 'dv_person',
    'dv_positions' => 'dv_positions',
    'dv_email_reply' => 'dv_email_reply',
    'dv_area_of_activity' => 'dv_area_of_activity',
    'dv_organisation_founder' => 'dv_organisation_founder',
    'dv_org_legal_status' => 'dv_org_legal_status',
    'dmt_mail' => 'dmt_mail',
    'dvm_mailing_list' => 'dvm_mailing_list',
    'dv_mailing_list' => 'dv_mailing_list',
    'dv_answer_text' => 'dv_answer_text',
    'dv_answer_number' => 'dv_answer_number',
    'ggroup' => 'ggroup', // we add ggroup here since it can't be enabled without any groups
    'dv_mailsystem_settings' => 'dv_mailsystem_settings',
    'dmt_organisation' => 'dmt_organisation',
    'dvm_user' => 'dvm_user',
    'dmt_domain_config' => 'dmt_domain_config',
    'dv_domain_dmtit_dev' => 'dv_domain_dmtit_dev',
    'dv_admin_dashboard' => 'dv_admin_dashboard',
  );

  $dv_modules = $modules;
  // Always install required modules first. Respect the dependencies between
  // the modules.
  $required = array();
  $non_required = array();

  // Add modules that other modules depend on.
  foreach ($modules as $module) {
    if ($files[$module]->requires) {
      $module_requires = array_keys($files[$module]->requires);
      // Remove the dv modules from required modules.
      $module_requires = array_diff_key($module_requires, $dv_modules);
      $modules = array_merge($modules, $module_requires);
    }
  }
  $modules = array_unique($modules);
  // Remove the dv modules from to install modules.
  $modules = array_diff_key($modules, $dv_modules);
  foreach ($modules as $module) {
    if (!empty($files[$module]->info['required'])) {
      $required[$module] = $files[$module]->sort;
    }
    else {
      $non_required[$module] = $files[$module]->sort;
    }
  }
  arsort($required);

  $operations = array();
  foreach ($required + $non_required + $dv_modules as $module => $weight) {
    $operations[] = array('_dv_install_module_batch', array(array($module), $module));
  }

  $batch = array(
    'operations' => $operations,
    'title' => t('Install DV modules'),
    'error_message' => t('The installation has encountered an error.'),
  );
  return $batch;
}

/**
 * @param $install_state
 */
function dv_final_site_setup(&$install_state) {
  // Clear all status messages generated by modules installed in previous step.
  drupal_get_messages('status', TRUE);

  node_access_needs_rebuild(TRUE); // There is no content at this point.

  $batch = array();
  /*
  $dv_optional_modules = \Drupal::state()->get('dv_install_optional_modules');
  foreach ($dv_optional_modules as $module => $module_name) {
    $batch['operations'][] = ['_dv_install_module_batch', array(array($module), $module_name)];
  }
  */

  // Add some finalising steps.
  $final_batched = [
    'profile_weight' => t('Set weight of profile.'),
    'router_rebuild' => t('Rebuild router.'),
    'config_import' => t('Import optional configuration.'),
    'cron_run' => t('Run cron.'),
    'node_access_rebuild' => t('Rebuild node access.')
  ];
  foreach ($final_batched as $process => $description) {
    $batch['operations'][] = ['_dv_finalise_batch', array($process, $description)];
  }

  return $batch;
}

/**
 * Performs final installation steps and displays a 'finished' page.
 *
 * @param $install_state
 *   An array of information about the current installation state.
 *
 * @return
 *   A message informing the user that the installation is complete.
 *
 * @see install_finished().
 */
function dv_install_finished(&$install_state) {
  // Clear all status messages generated by modules installed in previous step.
  drupal_get_messages('status', TRUE);

  if ($install_state['interactive']) {
    // Load current user and perform final login tasks.
    // This has to be done after drupal_flush_all_caches()
    // to avoid session regeneration.
    $account = User::load(1);
    user_login_finalize($account);
  }

}

/**
 * Implements callback_batch_operation().
 *
 * Performs batch installation of modules.
 */
function _dv_install_module_batch($module, $module_name, &$context) {
  set_time_limit(0);
  drush_print("b-----");
  drush_print_r($module);
  drush_print_r($module_name);
  drush_print("e-----");
  \Drupal::service('module_installer')->install($module);
  $context['results'][] = $module;
  $context['message'] = t('Install %module_name module.', array('%module_name' => $module_name));
}

/**
 * Implements callback_batch_operation().
 *
 * Performs batch uninstallation of modules.
 */
function _dv_uninstall_module_batch($module, $module_name, &$context) {
  set_time_limit(0);
  \Drupal::service('module_installer')->uninstall($module, $dependencies = FALSE);
  $context['results'][] = $module;
  $context['message'] = t('Uninstalled %module_name module.', array('%module_name' => $module_name));
}

/**
 * Implements callback_batch_operation().
 *
 * Performs batch finalising.
 */
function _dv_finalise_batch($process, $description, &$context) {

  switch ($process) {
    case 'profile_weight':
      $profile = drupal_get_profile();

      // Installation profiles are always loaded last.
      module_set_weight($profile, 1000);
      break;

    case 'router_rebuild':
      // Build the router once after installing all modules.
      // This would normally happen upon KernelEvents::TERMINATE, but since the
      // installer does not use an HttpKernel, that event is never triggered.
      \Drupal::service('router.builder')->rebuild();
      break;

    case 'cron_run':
      // Run cron to populate update status tables (if available) so that users
      // will be warned if they've installed an out of date Drupal version.
      // Will also trigger indexing of profile-supplied content or feeds.
      \Drupal::service('cron')->run();
      break;

    case 'config_import':
      // Import all optional configuration
      \Drupal::service('config.installer')->installOptionalConfig();
      break;

    case 'node_access_rebuild':
      node_access_rebuild();
      break;

  }

  $context['results'][] = $process;
  $context['message'] = $description;
}





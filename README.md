# GCEYE Configurations

### File to transfor to QA server.
```
apache2   
config  
docker-compose.yml
ssl_new
```

### docker image [https://hub.docker.com/repository/docker/iamapinan/gceye](https://hub.docker.com/repository/docker/iamapinan/gceye)   
to pull the image
```
docker pull iamapinan/gceye:5.8-ldap
```
### `gc_authen.php`
```PHP
<?php
/*
Plugin Name: GC Authen
Description: Active Directory Integration Plugin which already does the job for you.
*/

// protect direct access to file.
if (!defined('ABSPATH'))
    exit;
// init menu
add_action( 'admin_menu', 'gc_admin_menu' );
// Add menu to wordpress backend
function gc_admin_menu() {
	add_options_page( 'GC EYE AD', 'GC AD', 'manage_options', 'gc-ad-option', 'gc_plugin_admin_page' );
}
// Admin page
function gc_plugin_admin_page(){
    $mode = get_option( 'gc_mode' );
	if(isset($_POST['mode'])) {
        update_option('gc_mode', $_POST['mode']);
        $mode=$_POST['mode'];
    }
	?>
	<div class="wrap">
		<h2>Welcome To GC AD</h2>
        <div class="admin_container">
        	<form method="post">
                <p><select name="mode">
                    <option value="production" <?php echo ($mode == 'production') ? 'selected' : '';?>>Production mode</option>
                    <option value="test" <?php echo ($mode == 'test') ? 'selected' : '';?>>Test mode</option>
                </select></p>
                 <p><label>Production mode or Test mode (checked is production)</label></p>
                <input type="submit" value="Save" class="button button-primary">
          </form>
        </div>
	</div>

    <h3>Logs file</h3>
    <iframe width="100" height="500" src="/wp-content/plugins/gc_authen/log/" style="border: none;width: 100%;height: 600px;margin-top: 10px;"></iframe>
    <?php
}

function gc_authen($user = NULL, $username = '', $password = '') {
    if (empty($username) || empty($password)) {
        $user = new WP_Error( 'authentication_failed', __( '<strong>ERROR</strong>: Invalid username, email address or incorrect password.' ) );
        return $user;
    }
    // Get user info by username.
	$user = get_user_by('login', $username);
    
    // Do nothing for admin user
    if ($user->ID == 1) return false;

    $this_is_old = false;

	// Check is user already exists in db and send notification.
	if (is_object($user)) {
        $this_is_old = true;
    } else {
        $this_is_old = false;
    }
    
	// AD configurations
	$domain = 'pttgc';
	$endpoint = 'ldap://pttgc.corp:389';
	$dc = 'OU=PTTGCGroup,DC=pttgc,DC=corp';
    // AD data configs.
	$entries = [ "sn", "cn", "givenname", "mail", "displayname", "title", "company", "memberof" ];
    $mode = get_option( 'gc_mode' );
	
	// Connect to AD server.
	$ldap = @ldap_connect($endpoint);
	if(!$ldap){
        // If not success
        $user = new WP_Error( 'authentication_failed', __( '<strong>ERROR</strong>: Fail to connect to Active Directory Server.' ) );
        return $user;
	}

	// Set LDAP option.
	ldap_set_option($ldap, LDAP_OPT_PROTOCOL_VERSION, 3);
	ldap_set_option($ldap, LDAP_OPT_REFERRALS, 0);
    
	// Bind username and password.
    if($mode == 'production') {
    	$bind = @ldap_bind($ldap, "$domain\\$username", $password);
    }
	// Check if user is binding success.
	if(!$bind){
        // iF not return error.
        $user = new WP_Error( 'authentication_failed', __( '<strong>ERROR</strong>: Invalid username, email address or incorrect password.' ) );
        return $user;
        
	}
	// Search entries
    $result = @ldap_search($ldap, $dc, "(sAMAccountName=$username)", $entries);
    $info = @ldap_get_entries($ldap, $result);
    $filterGroup = preg_grep("/(CN=GC*)/", $info[0]['memberof']);
    
    $info['role'] = 'guest'; // force first time user to guest role.
    if($mode != 'production') // enable logging when in test mode
        file_put_contents(__DIR__ .'/log/'.$username.'.log', json_encode($info) );
        
    if( $this_is_old === true ) {
        // Update user password to new.
    	wp_set_password( $password, $user->ID );
            	
        // Initial user fullname.
        $fullname = $info[0]['givenname'][0].' '.$info[0]['sn'][0];
        // IF displayname != fullname
        if($user->displayname != $fullname) {
            // Update fullname
            wp_update_user([
                'ID' => $user->ID,
                'display_name' => $fullname,
            ]);
        }
        
        return $user;
    } else {
        $user = setUser($info, $username, $password, false);
        if($user != false) {
            return $user;
        }
    }

}


// Hook to login process.
add_filter('authenticate', 'gc_authen', 10, 3);

function setUser($info, $username, $password, $old) {
	
	$data = [];

	foreach($info[0] as $key => $value) {
		$data[$key] = (array)$value;
	}

	$data = [
		'mail' => $data['mail'][0],
		'displayname' => trim( $info[0]['givenname'][0].' '.$info[0]['sn'][0] ),
        'givenname' => $info[0]['givenname'][0],
        'sn' => $info[0]['sn'][0],
        'cn' => $info[0]['cn'][0],
        'title' => $info[0]['title'][0],
        'company' => $info[0]['company'][0]
	];
    
   
	// If we got here - then user can be logged in
    // If user info is not exists
	if($old === false) {
        // Create user
		$user_create = wp_create_user($data['cn'], $password, $data['mail']);
        
		// Update user info.
		wp_update_user([
			'ID' => $user_create,
            'nickname' => $data['displayname'],
            'display_name' => $data['displayname'],
            'first_name' => $data['givenname'],
            'last_name' => $data['sn']
		]);
        
        // Update user position.
        update_user_meta( $user_id, 'organization', $data['title'] . ' ' . $data['company']);
        
		// Get user object and set role for new user.
        $uObject = new WP_User($user_id);
		$uObject->set_role($info['role']);
		
        if(!isset($user_create['error'])) {
            return $user_create;
        } else {
            return false;
        }
	}
}
```
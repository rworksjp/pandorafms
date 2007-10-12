<?php
// Pandora FMS - the Free monitoring system
// ========================================
// Copyright (c) 2004-2007 Sancho Lerena, slerena@openideas.info
// Copyright (c) 2005-2007 Artica Soluciones Tecnologicas
// Copyright (c) 2004-2007 Raul Mateos Martin, raulofpandora@gmail.com
// Copyright (c) 2006-2007 Jose Navarro jose@jnavarro.net
// Copyright (c) 2006-2007 Jonathan Barajas, jonathan.barajas[AT]gmail[DOT]com

// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation version 2
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, U6

// Load global vars
require("include/config.php");
if (comprueba_login() == 0){ 
	$iduser_temp=$_SESSION['id_usuario'];
	if (give_acl($iduser_temp, 0, "AR") == 1){
		echo "<h2>".$lang_label["ag_title"]." &gt; ";
		echo $lang_label["db_stat_agent"]."</h2>";
		echo "<table border=0>";
		echo "<tr><td><img src='reporting/fgraph.php?tipo=db_agente_modulo'><br>";
		echo "<tr><td><br>";
		echo "<tr><td><img src='reporting/fgraph.php?tipo=db_agente_paquetes'><br>";
		echo "</table>";
	}
 	else {
		audit_db($id_user,$REMOTE_ADDR, "ACL Violation","Trying to access Agent estatistics");
		require ("general/noaccess.php");
	}
}
?>
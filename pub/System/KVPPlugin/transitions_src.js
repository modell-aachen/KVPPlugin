jQuery(document).ready(function() {
  WORKFLOWshowCheckBox = function() {
      var menu = jQuery('#WORKFLOWmenu');
      var remark = document.getElementById("KVPRemark");
      var selection = menu.val(); 
      if(selection === undefined) {
          menu = jQuery('#WORKFLOWbutton');
          if (menu === undefined) return;
          selection = menu.text().replace(/^\s+|\s+$/g, '');
      }
      if(remark != null) {
          if(WORKFLOWremarkOption.indexOf(','+selection+',') > -1) {
              remark.style.display = 'block';
          } else {
              remark.style.display = 'none';
          }
      }
      var box = document.getElementById("WORKFLOWchkbox");
      if (box === undefined || box === null) return;
      if(WORKFLOWallowOption.indexOf(','+selection+',') > -1) {
          box.style.display = 'inline';
          document.getElementById('WORKFLOWchkboxbox').checked = false;
      } else if (WORKFLOWsuggestOption.indexOf(','+selection+',') > -1) {
          box.style.display = 'inline';
          document.getElementById('WORKFLOWchkboxbox').checked = true;
      } else {
          box.style.display = 'none';
      }
  }
  jQuery('select').change(WORKFLOWshowCheckBox);
  WORKFLOWshowCheckBox();
});

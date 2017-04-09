<div class="w3-main w3-container" style="margin-left:270px;margin-top:117px;">

    <div class="w3-container w3-green w3-card-4 w3-center">
        <h2>Registered Users</h2>
    </div>

    <!--    Donor table -->
    <div class="w3-card-4 w3-light-grey">

        <?php
        $sql_select = "SELECT * FROM user LIMIT 0, 100";
        $stmt = $conn->query($sql_select);
        $users = $stmt->fetchAll();

        if(count($users) > 0)
        {?>
            <table class="w3-table-all">
                <thead>
                <tr class="w3-green">
                    <th>#</th>
                    <th>Username</th>
                    <th>Role</th>
                </tr>
                </thead>

                <?php
                $counter = 1;
                foreach($users as $user)
                {?>
                    <tr class="w3-hover-green">
                        <td><?= $counter?>.</td>
                        <td><?= $user['username']?></td>
                        <td><?= $user['role']?></td>
                    </tr>
                    <?php

                    $counter++;
                }?>
            </table>
            <?php
        }
        else
        {?>
            <h3>No one is currently registered.</h3>
            <?php
        } ?>
    </div>
</div>
